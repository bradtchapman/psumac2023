#!/bin/zsh

## REMEMBER TO POPULATE THE 4 SCRIPT PARAMETERS IN JAMF:
## PARAMETER 4 = AWS ACCESS KEY
## PARAMETER 5 = AWS SECRET KEY
## PARAMETER 6 = BUCKET@REGION (must be written this way)
## PARAMETER 7 = CUSTOMER (for MSPs). 
##### NOTE: Customer names will be stripped of spaces and punctuation.
##### Use letters and numbers only.

initScriptParameters() {
	
	# SCRIPT PARAMETERS
	# $1 $2 $3 ARE NOT USED (for compatibility with Jamf)
	# NOTE: $4 and $5 expect a base-64 encoded string
	# $6 must be in the format bucket@region
	
	aws_ak=$(echo "$4" | base64 -D)		# access key
	aws_sk=$(echo "$5" | base64 -D)		# secret key
	bucket="$(echo "$6" | awk 'BEGIN{FS="@"}{print $1}')"		# bucket name
	region="$(echo "$6" | awk 'BEGIN{FS="@"}{print $2}')"		# region name
	customer_long="$7"
	customer=$(echo "${7}" | tr -d "[:blank:]" | tr -d "[:punct:]")
	
	## If no customer field provided, set it to N/A.
	if [[ -z "$7" ]]
	then
		customer_long="N/A"
		customer="NA"
	fi

	itslog_workdir="/var/tmp/itslog"
	swd_commands="$itslog_workdir/swd_run.log"
	timeStamp=$(date -j +"%Y%m%d-%H%M%S")
	timeStampEpoch=$(date -j +"%s")
	secondsForSurvey="30"
	currentUser=$(ls -la /dev/console | awk '{ print $3 }')
	serialNumber=$(system_profiler SPHardwareDataType | awk -F":" '/Serial Number/ { gsub(/ /,""); print $2 }')
	modelID=$(system_profiler SPHardwareDataType | awk '/Model Identifier/ { print $3 }' | tr ',' '_')
	macOSvers=$(sw_vers | awk '/ProductVersion:/ { print $2 }')
	macOSbuild=$(sw_vers | awk '/BuildVersion/ { print $2 }')
	sysDiagArchive="itslog_${customer}_${timeStamp}_${currentUser}_${serialNumber}_${modelID}_${macOSvers}_${macOSbuild}"
	sysDiagTarball="$sysDiagArchive.tar.gz"
	surveyResponse="itslog_${customer}_${timeStamp}_${currentUser}_${serialNumber}_${modelID}_${macOSvers}_${macOSbuild}.txt"
	mini_window_open=false
	surveyStageDone=false
	surveyEmpty=false

	mkdir -p "$itslog_workdir"
	cd "$itslog_workdir"

}


# This function writes data to the swiftDialog command log
swd_echo() {
	echo "$1" | tee -a "$swd_commands"
}


# This function generates the AWS v4 Signatures & checksums required for upload.
#
# ADAPTED FROM THIS SCRIPT:
# https://very.busted.systems/shell-script-for-S3-upload-via-curl-using-AWS-version-4-signatures

generate_aws_keys() {

	srcfile=$1
	targfile=$2
#	acl="public-read"
	md5="$(openssl md5 -binary "$srcfile" | openssl base64)"
	
	# Create signature if not public upload.
	
	key_and_sig_args=''
	if [ "$aws_ak" != "" ] && [ "$aws_sk" != "" ]; then
		
		# Need current and file upload expiration date. Handle GNU and BSD date command style to get tomorrow's date.
		date="$(date -u +%Y%m%dT%H%M%SZ)"
		expdate="$(if ! date -v+1d +%Y-%m-%d 2>/dev/null; then date -d tomorrow +%Y-%m-%d; fi)"
		expdate_s="$(echo "$expdate" | sed s_-__g)"
		service='s3'
		
		# echo "Fields generated: date: $date - expdate: $expdate - expdate_s: $expdate_s - service: $service"
		
			# Generate policy and sign with secret key following AWS Signature version 4, below
			p=$(cat <<-POLICY | openssl base64
			{ "expiration": "${expdate}T12:00:00.000Z",
				"conditions": [
				{"bucket": "$bucket" },
				["starts-with", "\$key", ""],
				["content-length-range", 1, $(ls -l -H "$srcfile" | awk '{print $5}' | head -1)],
				{"content-md5": "$md5" },
				{"x-amz-credential": "$aws_ak/$expdate_s/$region/$service/aws4_request" },
				{"x-amz-algorithm": "AWS4-HMAC-SHA256" },
				{"x-amz-date": "$date" }
				]
			}
			POLICY
		)
			
			# echo "The value of POLICY is $p"
			
			# AWS4-HMAC-SHA256 signature
			s=$(echo -n "$expdate_s"   | openssl sha256 -hmac "AWS4$aws_sk"           -hex | sed 's_.*(stdin)= __g')
			s=$(echo -n "$region"      | openssl sha256 -mac HMAC -macopt hexkey:"$s" -hex | sed 's_.*(stdin)= __g')
			s=$(echo -n "$service"     | openssl sha256 -mac HMAC -macopt hexkey:"$s" -hex | sed 's_.*(stdin)= __g')
			s=$(echo -n "aws4_request" | openssl sha256 -mac HMAC -macopt hexkey:"$s" -hex | sed 's_.*(stdin)= __g')
			s=$(echo -n "$p"           | openssl sha256 -mac HMAC -macopt hexkey:"$s" -hex | sed 's_.*(stdin)= __g')
			
			key_and_sig_args="-F X-Amz-Credential=$aws_ak/$expdate_s/$region/$service/aws4_request -F X-Amz-Algorithm=AWS4-HMAC-SHA256 -F X-Amz-Signature=$s -F X-Amz-Date=${date}"
			
		fi
} 

launch_mini_window() {
	
	/usr/local/bin/dialog -d --commandfile "$swd_commands" \
	--mini --moveable --position center --ontop --icon "$icon" \
	--title "ITS-LOG: Upload in progress..." \
	--message "This window will close when all files are collected and uploaded." \
	--progress &
	
	mini_window_open=true
	surveyStageDone=true
	
}

#
##### SEQUENTIAL / RUNTIME FUNCTIONS
#
##### STAGE 1: Launch SwiftDialog
#

launchSurveyWindow() {

# Configure SwiftDialog
	
	position="center"
	quitkey="x"
	dialog_width="700"
	dialog_height="600"
	title="ITS-LOG: Crash Survey"
	titlefont="color=#ff6600,weight=bold,size=24"
	message="## Oh no! \n #### We're sorry that your Mac is having a problem.  Please tell us a little more about the most recent crash or issue that occurred. \n ##### If you're done, click [OK] ; processing will continue in the background. \n ###### NOTE: This tool collects diagnostic data from your Mac that will be transmitted to your IT department, who may require forwarding to Apple for additional analysis."
	messagefont="weight=light,size=18"
	icon="$itslog_workdir/sad-mac-8bit.png"
	iconsize=128
	dropdownsJSON='{ "selectitems" : [ { "title" : "Type of issue?", "values" : ["System crash or unexpected reboot","System is slow or unresponsive","One app crashed unexpected","Something else not on this list"] }, { "title" : "How frequently?", "values" : ["Immediately","After a few minutes","After a few hours","After a few days","It varies","It comes and goes","Unsure"] }, { "title" : "Last occurrence?", "values" : ["It is happening now","Less than 20 minutes ago","Less than 1 hour ago","1-6 hours ago","6-12 hours ago","12-24 hours ago","More than 24 hours ago","Unsure"] } ] }'

# Launch SwiftDialog
	
	/usr/local/bin/dialog -d --moveable --commandfile "$swd_commands" --quitkey "$quitkey" \
	--width "$dialog_width" --height "$dialog_height" --position "$position" \
	--title "$title" --titlefont "$titlefont" --icon "$icon" --iconsize "$iconsize" \
	--message "$message" --messagefont "$messagefont" \
	--textfield "Describe in detail:",editor,required \
	--textfield "What is your UID?",required,regex="^\d{9}$",regexerror="Company UID must be exactly 9 digits." \
	--jsonstring "$dropdownsJSON" \
	--progress \
	| tee "$surveyResponse" &

	/usr/bin/afplay -v 1.0 $itslog_workdir/itslog-crash-mac-8bit.m4a &
	
	sleep 1

}

#
##### STAGE 2: SYSDIAGNOSE COLLECTION
#

generateSysdiagnose() {
	
	/usr/bin/sysdiagnose -v -b -n -u -f "$itslog_workdir" -A "$sysDiagArchive" | cat &
	# /usr/bin/sysdiagnose -v -b -n -u -P -Q -G -R -F -f "$itslog_workdir" -A "$sysDiagArchive" | cat &
	# /usr/bin/sysdiagnose -v -b -n -u -P -Q -G -R -F -f "$itslog_workdir" -A "$sysDiagArchive" | cat &
	# /usr/bin/sysdiagnose -v -b -n -u -P -Q -f "$itslog_workdir" -A "$sysDiagArchive" | cat &
	
	swd_echo "progresstext: Gathering logs (about 3-5 minutes) ..."
	
	sleep 5

	# Keep checking until the sysdiagnose utility has finished.  
	# "Sysdiagnose is still running..."
	# If user finishes the survey before curl or sysdiagnose are completed...
	# Launch the mini window to keep them informed of its progress.

	while [[ -n $(pgrep "sysdiagnose_helper") ]]
	do
		
		if [[ -z $(pgrep -nx "Dialog") && $mini_window_open == false ]]
		then
			launch_mini_window
			swd_echo "progresstext: Gathering logs (about 3-5 minutes) ..."
		fi
		
		sleep 1
		
	done

	# Copy additional files intp the archive folder before compression   
	
	cp /var/log/jamf.log "$sysDiagArchive/"
	# cp /var/log/somefile1.log
	# cp /var/log/somefile2.log

	# Compress the archive into a "tarball" (.tar.gz)
	
	/usr/bin/tar -czf "$sysDiagTarball" "$sysDiagArchive/" &
	tarPID=$!
	
	echo "Compressing sysdiagnose archive..."
	
	swd_echo "progresstext: Compressing logs and preparing to upload."
	
	sleep 1

	
	# If user finishes the survey before curl or sysdiagnose are completed...
	# Launch the mini window to keep them informed of its progress.

	while [[ -n $(pgrep -nf "tar -czf") ]]
	do

		if [[ -z $(pgrep -nx "Dialog") && $mini_window_open == false ]]
		then
			launch_mini_window
			swd_echo "progresstext: Compressing logs and preparing to upload."
		fi
		
		sleep 0.5
		
	done

}

uploadSysdiagnose () {

	swd_echo "progress: 0"
	
	# Generate the AWS keys for the first file upload.
	generate_aws_keys "$sysDiagTarball" "itslog/logs/${customer}/$serialNumber/$sysDiagTarball"


	# Upload. Supports anonymous upload if bucket is public-writable, and keys are set to ''.
	echo "Uploading: $srcfile to $bucket:$targfile"
	
	# Upload the file to the S3 bucket.
	# s3-accelerate is a high speed conduit via CloudFlare.
	# The 2>&1 and tr > log bits are used to get the percentage progress
	# which is then passed to swiftDialog.
	
	uploadStageDone=false
	uploadSuccess=false
	
	#--retry 3 --retry-delay 5	\
	#--limit-rate 5M			\
	
	curl			  			\
	-Y 0 -y 10					\
	-F "key=$targfile"			\
	-F "X-Amz-Credential=$aws_ak/$expdate_s/$region/$service/aws4_request" \
	-F "X-Amz-Algorithm=AWS4-HMAC-SHA256" 	\
	-F "X-Amz-Signature=$s"		\
	-F "X-Amz-Date=${date}"		\
	-F "Policy=$p"				\
	-F "Content-MD5=$md5"		\
	-F "file=@$srcfile"			\
	"https://${bucket}.s3.${region}.amazonaws.com/" 2>&1 \
	| tr -u '\r' '\n' | tee "$itslog_workdir/curlout.txt" &
	curlPID=$(pgrep -P $$ curl)  
	# echo "the PID of curl is $curlPID."
	
	sleep 0.5
	
}

awaitUserSurvey() {

	until [[ $uploadStageDone == true && $surveyStageDone == true ]]
	do
		
		# If user finishes the survey before curl or sysdiagnose are completed...
		# Launch the mini window to keep them informed.
				
		while [[ -n $(pgrep -nx "curl") ]]
		do
			
			if [[ -z $(pgrep -nx "Dialog") && $mini_window_open == false ]]
			then
				launch_mini_window
				swd_echo "progresstext: Uploading logs:"
			fi
			
			sleep 0.5
			
			pctDone="$(tail -1 "$itslog_workdir/curlout.txt" | awk '{ print $1 }')"
			timeToFinish="$(tail -1 "$itslog_workdir/curlout.txt" | awk '{ print $11 }')"
			amountXferd="$(tail -1 "$itslog_workdir/curlout.txt" | awk '{ print $6 }')"
			totalSize="$(tail -1 "$itslog_workdir/curlout.txt" | awk '{ print $2 }')"
			echo "Time to finish is $timeToFinish"
			
			if [[ $timeToFinish != "--:--:--" ]]
			then
				timeLeft="$(date -j -u -f "%Y-%m-%d %H:%M:%S" "1970-01-01 $timeToFinish" +%M:%S)"
			else
				timeLeft="00:00"
			fi
			
			swd_echo "progresstext: Uploading: $pctDone%, $timeLeft left ($amountXferd of $totalSize) "
			swd_echo "progress: $pctDone"
		done
		
		if [[ $uploadStageDone == false ]]
		then
			# Read the file one last time.
			pctDone="$(tail -1 "$itslog_workdir/curlout.txt" | awk '{ print $1 }')"
			sleep 0.5
			
			# if the upload falls short or the transfer dies unexpectedly, error out.
			# Otherwise, play that little jingle on the xylophone and celebrate!
			
			if [[ $pctDone =~ "curl" || ! $pctDone =~ ^[0-9]{1,3} || $pctDone -lt "100" ]]
			then
				# FAIL - SAD PRICE IS RIGHT HORNS
				swd_echo "message: An error occurred while uploading.  Please try again, or contact your administrator."
				swd_echo "progresstext: ❌ Upload failed.  Closing in 10 seconds..."
				swd_echo "button1: enable"
				swd_echo "button1text: Sorry..."
				/usr/bin/afplay -v 1.0 "$itslog_workdir/itslog-fail-sad-horns.m4a" &
				sleep 10
				uploadStageDone=true
				uploadSuccess=false
			else
				
				# SUCCESS - HAPPY XYLOPHONE SOUNDS
				/usr/bin/afplay -v 1.0 "$itslog_workdir/itslog-success-xylophone.m4a" &
				if [[ $mini_window_open == true ]]
				then
					swd_echo "message: ✅ File uploaded successfully!"
					swd_echo "progresstext: All done!  Closing in 10 seconds..."
					swd_echo "button1: enable"
					swd_echo "button1text: Thank you!"

                    sleep 10
                    swd_echo "quit:"
				else
					swd_echo "progresstext: ✅ File uploaded! Please complete the survey ."
                    sleep 10
				fi
				timeStampEpoch=$(date -j +"%s")
				uploadSuccess=true
				uploadStageDone=true
			fi
		fi
				
		# If the user left the survey window open during the upload
		# This will check if they finally closed it out and help to exit the loop
		# So that their response can be uploaded to Amazon.
				
		if [[ -z $(pgrep -nx "Dialog") && $uploadStageDone == true && $mini_window_open == false ]]
		then
			surveyStageDone=true
		fi
		
		# However, if the user left the survey open for too long, we need to close it and move on.
		
		currentTimeEpoch="$(date -j +"%s")"
		surveyTimeLeft=$((secondsForSurvey - ((currentTimeEpoch - timeStampEpoch))))
		
		if [[ $uploadStageDone == true && $surveyStageDone == false ]]
		then
			swd_echo "progresstext: ⏳ Time left to submit survey: $surveyTimeLeft"
		fi
		
		if [[ $surveyStageDone == false && $((currentTimeEpoch - timeStampEpoch)) -ge $secondsForSurvey ]]
		then
			echo -e "NOTICE: Survey time expired.  No response was recorded." \
			> "$surveyResponse"
			swd_echo "quit:"
			surveyStageDone=true
			surveyEmpty=true
		fi

		sleep 0.5
		
	done
	
}

uploadSurvey() {

#	Diagnostic Link : https://${bucket}.s3.amazonaws.com/$targfile \n \
#	Log Filename    : $sysDiagTarball \n \

	# Prepends the Survey response with some data about the computer
	if [[ $surveyEmpty == false ]]
	then
		echo -e "\
Customer		: ${customer_long} \n \
Serial Number   : $serialNumber \n \
Logged In User  : $currentUser \n \
Mac Model ID    : $modelID \n \
MacOS Version   : $macOSvers ($macOSbuild) \n \
=========== \n\n \
$(cat "$surveyResponse")" > "$surveyResponse"
	fi	

	# Generate the keys for the survey responses and upload now.
	
	generate_aws_keys "${surveyResponse}" "itslog/surveys/${customer}/$serialNumber/${surveyResponse}"
	
	curl						\
	-F "key=$targfile"			\
	-F "X-Amz-Credential=$aws_ak/$expdate_s/$region/$service/aws4_request" \
	-F "X-Amz-Algorithm=AWS4-HMAC-SHA256" 	\
	-F "X-Amz-Signature=$s"		\
	-F "X-Amz-Date=${date}"		\
	-F "Policy=$p"				\
	-F "Content-MD5=$md5"		\
	-F "file=@$srcfile"			\
	"https://${bucket}.s3.{$region}.amazonaws.com/" 2>&1 \
	| tr -u '\r' '\n' | tee "$itslog_workdir/curlout-survey.txt"
	
}

cleanUp() {
	
	echo "Cleaning up log and temporary files..."
	
	/bin/rm -rf "${sysDiagArchive}"
	/bin/rm -rf "${sysDiagTarball}"
	/bin/rm -rf "${surveyResponse}"
    swd_echo "quit:"
	
}

######## MAIN SEQUENCE

echo "Stage 0: initializing script parameters..."
initScriptParameters "$1" "$2" "$3" "$4" "$5" "$6" "$7"

######## An instance of swiftDialog is launched immediately

main() {
		
	echo "Stage 0: Launching survey window..."
	launchSurveyWindow 

	echo "Stage 1: Generating sysdiagnose logs (waits for completion)."
	generateSysdiagnose

	echo "Stage 2: Uploading sysdiagnose logs (backgrounded, returning control)"
	uploadSysdiagnose 
	
	echo "Stage 3: Waiting for user to complete survey..."
	awaitUserSurvey 
	
	echo "Stage 4: Survey stage has finished.  Uploading response..."
	uploadSurvey
	
	echo "Stage 5: Cleaning up temporary files..."
	#cleanUp 

	echo "SCRIPT COMPLETE."
	
}

main

if [[ $uploadSuccess == false ]]
then
	echo "ERROR: ITS-LOG encountered a problem while uploading the file to Amazon.  Please check!"
	#cleanUp
    exit 1
    
fi

exit 0



