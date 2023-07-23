# Run Book

## Logging into AWS
1. Log into AWS Console - https://aws.amazon.com
2. Authenticate with MFA 

## Simple Notification Service
1. Search for SNS in the toolbar.
2. Choose a region before you start (e.g. Ohio / us-east-2)

### Create a topic
- Standard Delivery
- Name: itslog-survey-sns
- Display Name: ITS-LOG Survey
- Access Policy: basic, don’t change anything
- Leave other settings alone

### Create a subscription
- Select topic you just made
- Protocol: email
- Create subscription
- Confirm email

## S3 Bucket
Search for S3.  
Confirm region is the same as your SNS

### Create bucket
- Click [Create bucket]
- Name
- Region
- Leave other settings default
- Click [Create Bucket]

### Lifecycle Rules
- Click [Create lifecycle rule]
- Name
- Rule scope: limit scope using filter
- Filter type: Prefix: itslog/*
- [x] Expire current
- [x] Permanently Delete non-current
- Expire after 7 days
- Delete 1 day later
- Click [Create Rule]

Note: folders are automatically recreated by ITS-LOG when objects are uploaded to S3, so it’s fine if they get deleted by the lifecycle policy.

## Lambda
Note the current region; set it up in the same one as your S3 bucket.

### Create function
- Click [Create function]
- Name
- Runtime: Node.js 16.x
- Arch: x86_64
- Permissions: change default execution role
- Create role from policy templates:
- S3 object read-only permissions
- SNS publish policy
- Wait ~30 seconds.

### S3 Trigger
- Click [Add Trigger]
- Search for the S3 service
- Event: “all object create events” (default)
- Prefix: itslog/surveys/
- Suffix: .txt
- Acknowledge the recursion warning…
- Click “Add.”

### Insert Code
- Select Code tab.
- Replace the ‘hello world’ sample with actual ITS-LOG Lambda function.
- Edit email body
- Edit email subject
- Lambda will publish directly to the SNS service via internal API
- File > Save.
- Click [Deploy]

## Identity & Access Management

### Create Policy
- Go to IAM dashboard > Policies
- Click [Create policy]
- Use Visual editor
- Search for and click “S3”
- Actions allowed: search for “PutObject”
- Check Write: [x] PutObject
- Click [Next]
- Resource: Add Arn
- Bucket name: bucketname/prefix
- Resource name: *
- Copy the last field value (arn:aws:s3:::bucket/prefix/*)
- Click [Add ARNs]

### Create User
- Go to IAM Dashboard > Users
- Click [Add User]
- Enter a username
- NO access to console
- Click Next.
- Attach policies directly
- Search for the itslog IAM policy
- No permissions boundary

### Create Access Key
- Select new user
- Go to ‘Security Credentials’ tab.
- Click [Create access key]
- Review Best Practices.
- App Running Outside AWS
- Click Next
- Optional tag
- Create Access Key
- Save the .CSV file

### Encode Access and Secret Keys
- Open Terminal
- echo “insert key value here” | base64
- Repeat for secret key
- Keep them secret.
 ### Bucket Policy
- Go back to IAM Users
- Select itslog user
- Copy IAM User ARN (arn:aws:iam:::123456789012…)
- Go back to S3 bucket
- Permissions: Edit
- Click [Policy Generator] (opens old school site)
- Type of policy: S3 bucket
- Effect: Allow
- Principal: IAM User ARN
- Actions: [x] PutObject
- Resource: same as the resource ARN from IAM policy
- Click [Add Statement]
- Click [Generate Policy]
- Copy and paste into S3 bucket policy.
- Click [Save changes].


