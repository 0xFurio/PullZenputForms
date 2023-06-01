import os
import requests
import json
import boto3 # I HATE BOTO3

ZENPUT_API_KEY = os.environ['ZENPUT_API_KEY'] # import Zenput API key from environment variables
SENDGRID_API_KEY = os.environ['SENDGRID_API_KEY'] # import Sendgrid API key from environment variables


def lambda_handler(event, context):
    def get_forms(form): # takes form id as parameter, returns a list of most recent submission ids for that form
        form_id = form
        base_url = 'https://www.zenput.com/api/v3/submissions' # always use this endpoint
        parameters = '?form_template_id=' + form_id
        limit = 10 # how many forms to pull, can be changed but seems to work best as 10
        request_url = base_url + parameters + '&start=0&limit=' + str(limit) # start should be 0, starts with most recent form and returns 0 + limit forms total

        headers = {
        "accept": "application/json",
        "X-API-TOKEN": ZENPUT_API_KEY
        }
    
        response = requests.get(request_url, headers=headers).json()
        submissions = []

        count = 0
        while count < limit:
            submission =  response['data'][count]['legacy_submission_id'] # data corresponds with a dictionary nested in a list... AND WHY IS IT LEGACY????
            submissions.append(submission)
            count += 1
        return submissions

    def send_notification(submission):
        sns = boto3.client('sns')
        response = sns.publish(TopicArn=os.environ['SNS_ARN'], Message=submission)
        return response

    def sns_output(submissions):
        for submission in submissions:
            send_notification(submission)

    def query_dynamodb(form):
        dynamodb = boto3.client('dynamodb')
        try:
            response = dynamodb.get_item(TableName=os.environ['DynamoTable'], Key={'FormID': {'S':form}}) # boto3 documentation sucks but FormID is PK of table
            if response['Item']['FormID']['S'] == form: # this will error out if the item is not in dynamoDB, triggering the except
                return True # true = form is in table
        except:
            response = dynamodb.put_item(TableName=os.environ['DynamoTable'], Item={'FormID': {'S':form}}) # make sure Item set here matches Key above ^^
            return False # false = form not in table
    
    def dedup_forms(submissions):
        new = [] # list of forms that have not been processed
        for submission in submissions:
            result = query_dynamodb(submission)
            if result == True:
                pass # form in table, don't send
            else:
                new.append(submission) #
        return new
    
    def main():
        forms = ['70689', '345105'] #list of forms to pull
        for form in forms:
            submissions = get_forms(form)
            new_forms = dedup_forms(submissions)
            sns_output(new_forms)

    main()
