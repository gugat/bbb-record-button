Record Button Feature for Record and Playback
============

Implemented for webcam and desktop currently


Changes

### generators/audio.rb ### 
  Add method trim_audio_rb(input_audio, output_audio_piece, start,stop)

generators/audio_processor.rb
  Add method process_rb(archive_dir, ogg_file)

generators/events.rb
  Add in Events
    get_start_and_stop_rec_events(events_xml)
    match_start_and_stop_rec_events(rec_events)

generators/video.rb
  Add in BigBlueButton
    process_webcam_rb(target_dir, temp_dir, meeting_id) 
    process_desktop_sharing_rb(target_dir, temp_dir, meeting_id)
    find_recorded_pieces_and_blanks_of_media(matched_media_evts,matched_rec_evts)
    media_was_recorded?(media_start, media_stop, rec_start, rec_stop)
    trim_recorded_pieces_of_video(pieces_events, orig_dir, dest_dir, orig_media_prefix="")
    #Commented trim_video(input_video, output_video_piece, start,stop) 
    relative_secs(init_time, final_time)
    convert_video_to_webm(video_in, video_out)
    trim_video(start, duration, video_in, video_out)
