open Lwt
open Cohttp_lwt_unix
open Yojson.Basic.Util

type user_info = {
  username: string;
  profile_image_url: string;
}

let extract_user_info json =
  let user = json |> member "content" |> member "itemContent" |> member "user_results" |> member "result" |> member "legacy" in
  let username = user |> member "screen_name" |> to_string in
  let profile_image_url = user |> member "profile_image_url_https" |> to_string |> Str.global_replace (Str.regexp "_normal") "" in
  let is_mutual = (user |> member "followed_by" |> to_bool) && (user |> member "following" |> to_bool) in
  if is_mutual then Some { username; profile_image_url } else None

let process_followers_file file_path =
  let json = Yojson.Basic.from_file file_path in
  let instructions = json |> member "data" |> member "user" |> member "result" |> member "timeline" |> member "timeline" |> member "instructions" |> to_list in
  let entries = List.fold_left (fun acc instruction ->
    match instruction |> member "entries" with
    | `Null -> acc
    | entries -> acc @ (entries |> to_list)
  ) [] instructions in
  let mutuals = List.filter_map (fun entry ->
    if (entry |> member "content" |> member "entryType" |> to_string) = "TimelineTimelineItem"
    then extract_user_info entry
    else None
  ) entries in
  Printf.printf "Found %d mutuals in %s\n" (List.length mutuals) file_path;
  mutuals

let download_profile_picture folder user =
  let open Lwt.Syntax in
  let* response, body = Client.get (Uri.of_string user.profile_image_url) in
  match response.status with
  | `OK ->
      let* content = Cohttp_lwt.Body.to_string body in
      let file_extension = Filename.extension user.profile_image_url in
      let file_path = Filename.concat folder (user.username ^ file_extension) in
      let* () = Lwt_io.with_file ~mode:Lwt_io.Output file_path (fun oc ->
        Lwt_io.write oc content
      ) in
      Lwt_io.printf "Downloaded profile picture for @%s\n" user.username
  | _ ->
      Lwt_io.printf "Failed to download profile picture for @%s\n" user.username

let ensure_directory_exists folder =
  Lwt_unix.file_exists folder >>= fun exists ->
  if not exists then
    Lwt_unix.mkdir folder 0o755
  else
    Lwt.return_unit

let main folder files =
  let all_mutuals = List.concat_map process_followers_file files in
  Lwt_main.run (
    ensure_directory_exists folder >>= fun () ->
    Lwt_list.iter_p (download_profile_picture folder) all_mutuals >>= fun () ->
    Lwt_io.printf "Finished downloading %d profile pictures to %s\n" (List.length all_mutuals) folder
  )

open Cmdliner

let folder =
  let doc = "Folder to save profile pictures." in
  Arg.(value & opt string "mutuals" & info ["folder"] ~docv:"FOLDER" ~doc)

let files =
  let doc = "Followers JSON file(s) to process." in
  Arg.(non_empty & pos_all file [] & info [] ~docv:"FILES" ~doc)

let fetch_moots_t = Term.(const main $ folder $ files)

let cmd =
  let doc = "Download Twitter mutual followers' profile pictures" in
  let man = [
    `S Manpage.s_description;
    `P "$(tname) processes Twitter followers JSON files and downloads profile pictures of mutual followers.";
  ] in
  let info = Cmd.info "fetch_moots" ~doc ~man in
  Cmd.v info fetch_moots_t

let () = exit (Cmd.eval cmd)
