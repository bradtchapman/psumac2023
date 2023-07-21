// Sources:
// https://stackoverflow.com/questions/30651502/how-to-get-contents-of-a-text-file-from-aws-s3-using-a-lambda-function
// https://stackoverflow.com/questions/38831829/nodejs-aws-sdk-s3-generate-presigned-url
// The trigger for this function is the S3 bucket
// Event type: s3:ObjectCreated:*
// Prefix: itslog/surveys/

var snsTopicARN = "arn:aws:sns:us-west-2:123456789012:sns-topic-name";
var util = require('util')
var AWS = require('aws-sdk');
var s3 = new AWS.S3();

exports.handler = function(event, context, callback) {
    
// Use the event passed from S3 to Lambda to retrieve
// the parameters necessary to run this function.

    var s3Event = event.Records[0];
    var srcBucket = s3Event.s3.bucket.name;
    var srcRegion = s3Event.s3.bucket.awsRegion;
    var srcEvent = s3Event.eventName;
    var srcTime = s3Event.eventTime;
    var srcKey = s3Event.s3.object.key;

// Obtain the key for the sysdiagnose file using the survey file key.
// NOTE: filenames differ by their prefix (path) and suffix (extension).
// Modify at your own risk.

    var sysdiagnoseObject = srcKey.replace("surveys", "logs");
    var sysdiagnoseObject = sysdiagnoseObject.replace(".txt", ".tar.gz");
    var signedUrlValidSeconds = 86400*7;
    var signedUrlValidDays = Math.round(signedUrlValidSeconds / 86400);

// Generate Signed URL:

	var signedUrl = s3.getSignedUrl('getObject', {
		Bucket: srcBucket,
		Key: sysdiagnoseObject,
		Expires: signedUrlValidSeconds
	})

// Retrieve the survey file and capture the raw text.

    let Bucket = srcBucket;
    let Key = decodeURIComponent(srcKey.replace(/\+/g, ' '));
    s3.getObject({ Bucket, Key }, function(err, data) {

    if (err) {
        console.log(err, err.stack);
        callback(err);
    } else {
        var srcBody = data.Body.toString("ascii");
        console.log("Raw text:\n" + data.Body.toString('ascii'));
        callback(null, null);
    }
        
// Construct the message being sent to SNS.
// This publishing method allows you to customize
// the subject and message body.

        var msg =   "ITS-LOG: A user calls for aid!  \r\n" +
                    "Survey responses below: \r\n" +
                    "---------------------------- \r\n\r\n" +
                    srcBody + "\r\n\r\n" +
                    "DOWNLOAD SYSDIAGNOSE FILE NOW.  Link expires " + 
                    signedUrlValidDays + " day(s) after time sent: \r\n\r\n" +
                    signedUrl + "\r\n\r\n" +
                    "S3 Bucket : " + srcBucket + "\r\n" +
                    "File (key): " + srcKey + "\r\n";
                  
        var sns = new AWS.SNS();
        
        sns.publish(
        {
          Subject: "ITS-LOG: Survey Recorded",
          Message: msg,
          TopicArn: snsTopicARN
        },

        function(err, data) 
        {
            
            if (err) 
            {
              console.log(err.stack);
              return;
            }
            
        // Debugging Junk
          console.log('Sysdiagnose srcKey and key values');
          console.log(srcKey);
		  console.log('Sysdiagnose signed URL:');
		  console.log(signedUrl);
          console.log(sysdiagnoseObject);
          console.log(msg);
          console.log(s3Event);
          console.log('Push Sent');
          
          
          context.done(null, 'Function Finished!');  
          
        });
    });
};


