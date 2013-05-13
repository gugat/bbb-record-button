# Support for record button

## Description

This directory contains files to support the "Record Button" feature in  "Record and Playback" component in a BigBlueButton server.

To support the record button some generators (events.rb, audio_processor.rb, audio.rb and video.rb) needed new methods, those methods
are not included in those files but in a unique file named record_button_generator.rb


## Deploy

Copy the generators and other necessary files

	chmod +x deploy.sh
	./deploy.sh


## How it works

We need to know when the user wants to start or stop the recording, those events are sent to the server as chat messages.
Behind scenes the session is all recorded, the start and stop events sent are used to trim the audio an video files.

## How to use

Create a recorded meeting, share desktop and webcam, and write in the chat window 'START' or 'STOP' (without quotes) 
when you want to start or stop the recording, log out. 

Go to demo10 and click the link to 'recbutton' next to the meeting id in the list of recordings.

## Note ##

This feature is under development, no warranties, thanks for any suggestion, pull requests are welcome.




