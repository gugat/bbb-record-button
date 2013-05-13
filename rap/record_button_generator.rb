module BigBlueButton
  #Trim audio file
  def self.trim_audio_rb(input_audio, output_audio_piece, start,stop) 
    duration = (stop - start).round(3)
    command = "ffmpeg -i #{input_audio} -acodec copy  -ss #{start} -t #{duration} #{output_audio_piece}"
    BigBlueButton.execute(command)       
  end



end
