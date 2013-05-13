module BigBlueButton
	
	############
	# audio.rb #
	############
	
	class AudioEvents
		#Trim audio file
		def self.trim_audio_rb(input_audio, output_audio_piece, start,stop) 
			duration = (stop - start).round(3)
			command = "ffmpeg -i #{input_audio} -acodec copy  -ss #{start} -t #{duration} #{output_audio_piece}"
			puts "----COMMAND----"
			puts "#{command}"
			BigBlueButton.execute(command)       
		end
	end
	
	######################
	# audio_processor.rb #
	######################
	
	class AudioProcessor
		#
		# Process the raw recorded audio to ogg file, according to the record button.
		#  archive_dir - directory location of the raw archives. Assumes there is audio file and events.xml present.
		#  ogg_file - the file name of the ogg audio output
		#
		def self.process_rb(archive_dir, ogg_file)
		  audio_dir = "#{archive_dir}/audio"
		  events_xml = "#{archive_dir}/events.xml"
		  audio_events = BigBlueButton::AudioEvents.process_events(audio_dir, events_xml)      
		  audio_files = []
		  first_no_silence = audio_events.select { |e| !e.padding }.first
		  sampling_rate = first_no_silence.nil? ? 16000 :  FFMPEG::Movie.new(first_no_silence.file).audio_sample_rate
		  audio_events.each do |ae|
			if ae.padding 
			  ae.file = "#{audio_dir}/#{ae.length_of_gap}.wav"
			  BigBlueButton::AudioEvents.generate_silence(ae.length_of_gap, ae.file, sampling_rate)
			else
			  # Substitute the original file location with the archive location
			  ae.file = ae.file.sub(/.+\//, "#{audio_dir}/")
			end
			
			audio_files << ae.file
		  end
		  
		  wav_file = "#{audio_dir}/prerecording.wav"
		  BigBlueButton::AudioEvents.concatenate_audio_files(audio_files, wav_file)   

		  rec_events = BigBlueButton::Events.get_start_and_stop_rec_events(events_xml)
	    
		  if rec_events.empty?
			#There is not usage of recording button          
			BigBlueButton::AudioEvents.wav_to_ogg(wav_file, ogg_file)
		  else
			#If record button is used then trim audio in desired recorded periods
			matched_rec_evts =  BigBlueButton::Events.match_start_and_stop_rec_events(rec_events)          
			record_started =  audio_events[0].start_record_timestamp
			audio_pieces = []  
			final_wav_file = "#{audio_dir}/recording.wav"
			matched_rec_evts.each_with_index do |evt,i|
				piece_start_sec = BigBlueButton.relative_secs(record_started, evt[:start_timestamp])
				piece_stop_sec = BigBlueButton.relative_secs(record_started, evt[:stop_timestamp])
				audio_piece_name = "#{audio_dir}/audio_piece_#{i}.wav"
				BigBlueButton::AudioEvents.trim_audio_rb(wav_file, audio_piece_name, piece_start_sec, piece_stop_sec) 
				audio_pieces << audio_piece_name
			  end
			BigBlueButton::AudioEvents.concatenate_audio_files(audio_pieces, final_wav_file)   	 
			BigBlueButton::AudioEvents.wav_to_ogg(final_wav_file, ogg_file)
		  end	
		end
	end
	
	#############
	# events.rb #
	#############
	
	module Events
	
		#		
		# Get events when the moderator wants the recording to start or stop
		#
		
		def self.get_start_and_stop_rec_events(events_xml)
		  BigBlueButton.logger.info "Getting start and stop rec button events"
		  rec_events = []
		  doc = Nokogiri::XML(File.open(events_xml))
		  #Comment this code below in production
		  a=doc.xpath("//event[@eventname='PublicChatEvent']")
		  BigBlueButton.logger.info "Extracting PublicChatEvent events" + a.size.to_s
		  a.each do |event|
			if not event.xpath("message[text()='START' or text()='STOP']").empty?
				  #rec_events << a             
				  event.attributes["eventname"].value ='RecordStatusEvent'
				  BigBlueButton.logger.info event.text()
			end
		  end
		  #Comment this code above in production
	   	  doc.xpath("//event[@eventname='RecordStatusEvent']").each do |event|
			s = {:start_timestamp => event['timestamp'].to_i}
			rec_events << s
		  end
		  if rec_events.size.odd?
			#User forgot to click Record Button to stop the recording
			rec_events << { :start_timestamp => BigBlueButton::Events.last_event_timestamp(events_xml) }
		  end      
		  rec_events.sort {|a, b| a[:start_timestamp] <=> b[:start_timestamp]}  
		end
		
		#
		# Match recording start and stop events
		#
		
		def self.match_start_and_stop_rec_events(rec_events)
		  matched_rec_events = []
		  rec_events.each_with_index do |evt,i|
			if i.even?
				   evt[:stop_timestamp] = rec_events[i+1][:start_timestamp]
				   matched_rec_events << evt
			end       
		  end
		  matched_rec_events     
		end
		
	end
	
	
	############
	# video.rb #
	############
	
	  #
	  # Process and trims the presenter webcam video according to the events of record button
	  #
	  
	   def self.process_webcam_rb(target_dir, temp_dir, meeting_id) 
		BigBlueButton.logger.info("Processing webcam")
		# Process audio

		# Process video    
		video_dir = "#{temp_dir}/#{meeting_id}/video/#{meeting_id}"
		blank_canvas = "#{temp_dir}/canvas.jpg"
		BigBlueButton.create_blank_canvas(MAX_VID_WIDTH, MAX_VID_HEIGHT, "white", blank_canvas)
				
		events_xml = "#{temp_dir}/#{meeting_id}/events.xml"
		first_timestamp = BigBlueButton::Events.first_event_timestamp(events_xml)
		last_timestamp = BigBlueButton::Events.last_event_timestamp(events_xml)        
		
		start_video_evt = BigBlueButton::Events.get_start_video_events(events_xml)
		stop_video_evt = BigBlueButton::Events.get_stop_video_events(events_xml)               
		matched_video_evts = BigBlueButton::Events.match_start_and_stop_video_events(start_video_evt, stop_video_evt)   

		rec_events = BigBlueButton::Events.get_start_and_stop_rec_events(events_xml)
		matched_rec_evts =  BigBlueButton::Events.match_start_and_stop_rec_events(rec_events)             

		piece_events, blank_events = find_recorded_pieces_and_blanks_of_media(matched_video_evts,matched_rec_evts)  
		
		# Remove audio from webcam videos and scale them
		matched_video_evts.each do |evt|
			stripped_webcam = "#{temp_dir}/stripped-wc-#{evt[:stream]}.flv"
			BigBlueButton.strip_audio_from_video("#{video_dir}/#{evt[:stream]}.flv", stripped_webcam)        
			scaled_flv = "#{temp_dir}/#{meeting_id}/scaled-wc-#{evt[:stream]}.flv"
			frame_size = BigBlueButton.scale_to_640_x_480(BigBlueButton.get_video_width(stripped_webcam),
														  BigBlueButton.get_video_height(stripped_webcam))       
			width = frame_size[:width]
			height = frame_size[:height]
			frame_size = "-s #{width}x#{height}"
			  side_padding = ((MAX_VID_WIDTH - width) / 2).to_i
			  top_bottom_padding = ((MAX_VID_HEIGHT - height) / 2).to_i
			padding = "-vf pad=#{MAX_VID_WIDTH}:#{MAX_VID_HEIGHT}:#{side_padding}:#{top_bottom_padding}:FFFFFF"       
			  command = "ffmpeg -i #{stripped_webcam} -aspect 4:3 -r 1000 -vcodec copy #{frame_size} #{padding} #{scaled_flv}" 
			BigBlueButton.execute(command)
		end     
	   
		video_pieces = BigBlueButton.trim_recorded_pieces_of_video(piece_events, "#{temp_dir}/#{meeting_id}",temp_dir, "scaled-wc-")    

		blank_events.each_with_index do |paddings, i|
		  paddings.each do |padding|
			duration = BigBlueButton.relative_secs(padding[:start_timestamp], padding[:stop_timestamp])		
			file = "#{video_dir}/#{padding[:stream]}"
			BigBlueButton.create_blank_video(duration, 1000, blank_canvas, file)                    
			padding[:file] = file
		  end
		end
			  
		blank_events.each do |paddings|
			video_pieces.concat(paddings)    
		end
		webcam_flow = video_pieces.sort{|a,b| a[:start_timestamp] <=> b[:start_timestamp]}
		webcam_flow_files = webcam_flow.map{ |p| p[:file]}
		p webcam_flow_files
		#Concatenate trimmed videos and blanks
		concat_vid = "#{target_dir}/webcam.flv"
		BigBlueButton.concatenate_videos(webcam_flow_files, concat_vid)    
		BigBlueButton.convert_video_to_webm(concat_vid,"#{target_dir}/webcam.webm")
	  end

	  #
	  # Process and trims the shared desktop video according to the events of record button
	  #
	  

	  def self.process_desktop_sharing_rb(target_dir, temp_dir, meeting_id)                
	 
		deskshare_dir = "#{temp_dir}/#{meeting_id}/deskshare" 
		blank_canvas = "#{temp_dir}/ds-canvas.jpg"
		BigBlueButton.create_blank_canvas(MAX_VID_WIDTH, MAX_VID_HEIGHT, "white", blank_canvas)
		
		events_xml = "#{temp_dir}/#{meeting_id}/events.xml"
		first_timestamp = BigBlueButton::Events.first_event_timestamp(events_xml)
		last_timestamp = BigBlueButton::Events.last_event_timestamp(events_xml)
			
		start_evts = BigBlueButton::Events.get_start_deskshare_events(events_xml)
		stop_evts = BigBlueButton::Events.get_stop_deskshare_events(events_xml)
					
		matched_video_evts = BigBlueButton::Events.match_start_and_stop_video_events(start_evts, stop_evts)        

		rec_events = BigBlueButton::Events.get_start_and_stop_rec_events(events_xml)
		matched_rec_evts =  BigBlueButton::Events.match_start_and_stop_rec_events(rec_events)             

		piece_events, blank_events = find_recorded_pieces_and_blanks_of_media(matched_video_evts,matched_rec_evts)	
		  piece_events.each do |event|
		  event[:stream] = event[:stream].gsub(".flv","")
		end
		
		# Remove audio from webcam videos and scale them
		matched_video_evts.each do |evt|            
		original_deskshare = "#{deskshare_dir}/#{evt[:stream]}"
		scaled_flv = "#{temp_dir}/#{meeting_id}/scaled-ds-#{evt[:stream]}"
			frame_size = BigBlueButton.scale_to_640_x_480(BigBlueButton.get_video_width(original_deskshare),
														  BigBlueButton.get_video_height(original_deskshare))
			width = frame_size[:width]
			height = frame_size[:height]
			frame_size = "-s #{width}x#{height}"
			side_padding = ((MAX_VID_WIDTH - width) / 2).to_i
			top_bottom_padding = ((MAX_VID_HEIGHT - height) / 2).to_i
			padding = "-vf pad=#{MAX_VID_WIDTH}:#{MAX_VID_HEIGHT}:#{side_padding}:#{top_bottom_padding}:FFFFFF"       
			command = "ffmpeg -i #{original_deskshare} -aspect 4:3 -r 1000  -vcodec flashsv #{frame_size} #{padding} #{scaled_flv}" 
			BigBlueButton.execute(command)       
		end     

		video_pieces = BigBlueButton.trim_recorded_pieces_of_video(piece_events, "#{temp_dir}/#{meeting_id}",temp_dir, "scaled-ds-")    
		blank_events.each_with_index do |paddings, i|
		  paddings.each do |padding|
			duration = BigBlueButton.relative_secs(padding[:start_timestamp], padding[:stop_timestamp])		
			file = "#{deskshare_dir}/#{padding[:stream]}"
			BigBlueButton.create_blank_deskshare_video(duration, 1000, blank_canvas, file)                    
			padding[:file] = file
		  end
		end
	 
		blank_events.each do |paddings|
			video_pieces.concat(paddings)    
		end
		deskshare_flow = video_pieces.sort{|a,b| a[:start_timestamp] <=> b[:start_timestamp]}
		deskshare_flow_files = deskshare_flow.map{ |p| p[:file]}
	  
		#Concatenate trimmed videos and blanks
		concat_vid = "#{target_dir}/deskshare.flv"
		BigBlueButton.concatenate_videos(deskshare_flow_files, concat_vid)   
		BigBlueButton.convert_video_to_webm(concat_vid,"#{target_dir}/deskshare.webm")
	  end
	  

	  # 
	  # Search events of media and blanks that matches periods of record
	  # 
	  
	  def self.find_recorded_pieces_and_blanks_of_media(matched_media_evts,matched_rec_evts)
	   pieces_events = []
	   blanks_events = []  
		  
	   #Intersect record's period with media's periods
		matched_media_evts.each do |media_evt|
			media_start = media_evt[:start_timestamp]
			media_stop = media_evt[:stop_timestamp]                

			matched_rec_evts.each do |rec_evt|                            
			  rec_start = rec_evt[:start_timestamp]
			  rec_stop = rec_evt[:stop_timestamp]                
			  #Is this media file or stream in a record period ?
			  if media_was_recorded?(media_start, media_stop, rec_start, rec_stop)                            
				#Check init of the record      
				piece_start_ts = rec_start > media_start ? rec_start : media_start
				piece_stop_ts = rec_stop < media_stop ? rec_stop : media_stop                             
				pieces_evt = { :start => relative_secs(media_start, piece_start_ts) ,
						 :stop => relative_secs(media_start, piece_stop_ts),
						 :start_timestamp => piece_start_ts,
						 :stop_timestamp =>  piece_stop_ts,
						 :stream =>  media_evt[:stream]                             
				}           
				pieces_events << pieces_evt                     
				if rec_evt[:media_evts].nil?
				  rec_evt[:media_evts] = Array.new
				end                      
				rec_evt[:media_evts] << pieces_evt                  
			  end                                     
			end       
		 end 
		 p matched_rec_evts    
		 matched_rec_evts.each_with_index do |rec_evt,i|
		   p rec_evt[:media_evts]
		   rec_start = rec_evt[:start_timestamp]
		   rec_stop = rec_evt[:stop_timestamp]        
		   if rec_evt[:media_evts].nil?
			blanks_events << [{ :start_timestamp => rec_start, 
							   :stop_timestamp => rec_stop,
							   :stream => "record_#{i}_blank.flv"}]      
		   else               
			 paddings = BigBlueButton.generate_deskshare_paddings(rec_evt[:media_evts], rec_start, rec_stop)
			 paddings.each { |p| p[:stream] = "record_#{i}_"+p[:stream]}         
			 blanks_events << paddings
		   end        
		 end
		 #When media occurs during all record period generate_deskshare_paddings throws empty arrays
		 blanks_events.delete_if { |padding| padding.empty? } 
		 return pieces_events ,blanks_events
	  end




	  #
	  # Check if the period of existence of the media matches a period of record
	  # 
	  
	  def self.media_was_recorded?(media_start, media_stop, rec_start, rec_stop)
		  cond1 = rec_start > media_start && rec_start < media_stop
		  cond2 = rec_stop > media_start && rec_stop < media_stop
		  cond3 = media_start > rec_start && media_stop < rec_stop
		  cond1 || cond2 || cond3
	  end      
	  
	  
	  
	  # 
	  # Generate new video files trimming an original video 
	  # 
	  
	  def self.trim_recorded_pieces_of_video(pieces_events, orig_dir, dest_dir, orig_media_prefix="")
		#Before webcam videos are stripped or scaled before trimmed.
		#orig_media_prefix let you specify the media prefix e.g scaled-wc,stripped-wc,scaled-       
		   
		pieces_events.each_with_index do |piece_evt, i|
			 original_stream = "#{orig_dir}/#{orig_media_prefix}#{piece_evt[:stream]}.flv"
			 trimmed_piece = "#{dest_dir}/piece_#{piece_evt[:stream]}_#{i}.flv"
			 start = piece_evt[:start] * 1000
			 stop = piece_evt[:stop] * 1000
			 #BigBlueButton.trim_video(original_stream, trimmed_piece, start,stop)        
				BigBlueButton.trim_video(start, stop - start, original_stream, trimmed_piece)
			 piece_evt[:file] = trimmed_piece
		end    
	  end    
	  
	  
	  # 
	  # Trim a video
	  # 
	  
	  #def self.trim_video(input_video, output_video_piece, start,stop) 
	  #      duration = stop - start
	  #      command = "ffmpeg -i #{input_video} -vcodec copy -acodec copy -ss #{start} -t #{duration}  #{output_video_piece}"
	  #      puts "----COMMAND----"
	  #     puts "#{command}"
	  #     BigBlueButton.execute(command)
	  #end
	  
	  
	  #
	  # Generate duration from init_time to final_time
	  #
	  
	  def self.relative_secs(init_time, final_time)
		   ( (final_time - init_time) / 1000.0 ).round(3)
	  end
	  
	  def self.convert_video_to_webm(video_in, video_out)
		command = "ffmpeg  -i #{video_in} -loglevel fatal -v -10 -vcodec libvpx -b 1000k -threads 0 #{video_out}"
		BigBlueButton.execute(command)
	  end
	  
	  # Generates a new video file given a start point and a duration
	  #   start - start point of the video_in, in milisseconds
	  #   duration - duration of the new video file, in milisseconds
	  #   video_in - the video to be used as base
	  #   video_out - the resulting new video
	  def self.trim_video(start, duration, video_in, video_out)
		BigBlueButton.logger.info("Task: Trimming video")
		
=begin
		command = "ffmpeg -i #{video_in} -loglevel fatal -vcodec copy -acodec copy -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} #{video_out}"
		#Good quality
		#Videos are shorter
		#They start after I want, a part at the beginning is trimmed.

		command = "ffmpeg -ss #{BigBlueButton.ms_to_strtime(start)} -i #{video_in} -loglevel fatal -vcodec copy -acodec copy  -t #{BigBlueButton.ms_to_strtime(duration)} #{video_out}"
		command = "ffmpeg -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} -i #{video_in} -loglevel fatal -vcodec copy -acodec copy   #{video_out}"
		#Good quality
		#Videos are shorter
		#They start before I want, a part at the beginning is extra. 
		
		#Usando como codec flv
		command = "ffmpeg -i #{video_in} -loglevel fatal -vcodec flv -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} #{video_out}"
		#Cambiando bitrate
		command = "ffmpeg -i #{video_in} -loglevel fatal -vcodec flv -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} -b:v 400k #{video_out}"
		#Poniendo el bitrate antes del codec
		command = "ffmpeg -i #{video_in} -loglevel fatal -b:v 400k -vcodec flv -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)}  #{video_out}"
		command = "ffmpeg -i #{video_in} -loglevel fatal -b:v 400k -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)}  #{video_out}"
		#Bad quality
		#Correct size
		#command = "ffmpeg -i #{video_in} -loglevel fatal -vcodec flv -acodec copy -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} #{video_out}"
		#Bad quality + correct size

		#command = "ffmpeg -ss #{BigBlueButton.ms_to_strtime(start)} -i #{video_in} -loglevel fatal -vcodec copy -acodec copy  -t #{BigBlueButton.ms_to_strtime(duration)} #{video_out}"
		
		
		#command = "ffmpeg -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} -i #{video_in} -loglevel fatal -vcodec copy -acodec copy  #{video_out}"
		#Video is delayed and has some extra content at the beginning

		#command = "ffmpeg -i #{video_in} -loglevel fatal -ss #{BigBlueButton.ms_to_strtime(start)} -t #{BigBlueButton.ms_to_strtime(duration)} #{video_out}"
		#bad quality + correct size 
=end
		command = "ffmpeg -i #{video_in} -loglevel fatal -vcodec copy -ss #{BigBlueButton.ms_to_strtime(start-1309.5)} -t #{BigBlueButton.ms_to_strtime(duration)}  #{video_out}"
		#between 1309 y 1310

	   
		BigBlueButton.execute(command)  
		# TODO: check for result, raise an exception when there is an error
	  end
end