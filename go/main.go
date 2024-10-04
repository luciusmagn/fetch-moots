package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

type UserInfo struct {
	Username         string
	ProfileImageURL string
}

func processFollowersFile(filePath string) ([]UserInfo, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	var data map[string]interface{}
	if err := json.NewDecoder(file).Decode(&data); err != nil {
		return nil, err
	}

	instructions := data["data"].(map[string]interface{})["user"].(map[string]interface{})["result"].(map[string]interface{})["timeline"].(map[string]interface{})["timeline"].(map[string]interface{})["instructions"].([]interface{})

	var mutuals []UserInfo

	for _, instruction := range instructions {
		inst := instruction.(map[string]interface{})
		if entries, ok := inst["entries"]; ok {
			for _, entry := range entries.([]interface{}) {
				e := entry.(map[string]interface{})
				if e["content"].(map[string]interface{})["entryType"].(string) == "TimelineTimelineItem" {
					user := e["content"].(map[string]interface{})["itemContent"].(map[string]interface{})["user_results"].(map[string]interface{})["result"].(map[string]interface{})["legacy"].(map[string]interface{})
					if user["followed_by"].(bool) && user["following"].(bool) {
						mutuals = append(mutuals, UserInfo{
							Username:        user["screen_name"].(string),
							ProfileImageURL: strings.Replace(user["profile_image_url_https"].(string), "_normal", "", 1),
						})
					}
				}
			}
		}
	}

	fmt.Printf("Found %d mutuals in %s\n", len(mutuals), filePath)
	return mutuals, nil
}

func downloadProfilePicture(user UserInfo, folder string, wg *sync.WaitGroup) {
	defer wg.Done()

	response, err := http.Get(user.ProfileImageURL)
	if err != nil {
		fmt.Printf("Failed to download profile picture for @%s: %v\n", user.Username, err)
		return
	}
	defer response.Body.Close()

	if response.StatusCode == http.StatusOK {
		if err := os.MkdirAll(folder, os.ModePerm); err != nil {
			fmt.Printf("Failed to create folder for @%s: %v\n", user.Username, err)
			return
		}

		fileExtension := filepath.Ext(user.ProfileImageURL)
		filePath := filepath.Join(folder, user.Username+fileExtension)

		file, err := os.Create(filePath)
		if err != nil {
			fmt.Printf("Failed to create file for @%s: %v\n", user.Username, err)
			return
		}
		defer file.Close()

		_, err = io.Copy(file, response.Body)
		if err != nil {
			fmt.Printf("Failed to save profile picture for @%s: %v\n", user.Username, err)
			return
		}

		fmt.Printf("Downloaded profile picture for @%s\n", user.Username)
	} else {
		fmt.Printf("Failed to download profile picture for @%s: status code %d\n", user.Username, response.StatusCode)
	}
}

func main() {
	folder := flag.String("folder", "mutuals", "Folder to save profile pictures")
	flag.Parse()

	files := flag.Args()
	if len(files) == 0 {
		fmt.Println("Usage: fetch_moots [--folder OUTPUT_FOLDER] [FILES]")
		return
	}

	var allMutuals []UserInfo
	for _, file := range files {
		mutuals, err := processFollowersFile(file)
		if err != nil {
			fmt.Printf("Error processing %s: %v\n", file, err)
			continue
		}
		allMutuals = append(allMutuals, mutuals...)
	}

	var wg sync.WaitGroup
	for _, mutual := range allMutuals {
		wg.Add(1)
		go downloadProfilePicture(mutual, *folder, &wg)
	}
	wg.Wait()

	fmt.Printf("Finished downloading %d profile pictures to %s\n", len(allMutuals), *folder)
}
