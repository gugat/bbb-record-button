changelog

* Add method trim_audio_rb(input_audio, output_audio_piece, start,stop)
* Add method process_rb(archive_dir, ogg_file)
* Add in Events get_start_and_stop_rec_events(events_xml)
* Add in Events match_start_and_stop_rec_events(rec_events)
* Add in BigBlueButton
* Add in BigBlueButton process_webcam_rb(target_dir, temp_dir, meeting_id)
* Add in BigBlueButton process_desktop_sharing_rb(target_dir, temp_dir, meeting_id)
* Add in BigBlueButton find_recorded_pieces_and_blanks_of_media(matched_media_evts,matched_rec_evts)
* Add in BigBlueButton media_was_recorded?(media_start, media_stop, rec_start, rec_stop)
* Add in BigBlueButton trim_recorded_pieces_of_video(pieces_events, orig_dir, dest_dir, orig_media_prefix="")
* Add in BigBlueButton Commented trim_video(input_video, output_video_piece, start,stop)
* Add in BigBlueButton relative_secs(init_time, final_time)
* Add in BigBlueButton convert_video_to_webm(video_in, video_out)
* Add in BigBlueButton trim_video(start, duration, video_in, video_out)

