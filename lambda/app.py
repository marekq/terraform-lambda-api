import json
from aws_lambda_powertools import Logger, Tracer

logger = Logger()
tracer = Tracer()

@logger.inject_lambda_context(log_event = True)
@tracer.capture_lambda_handler(capture_response = True)
def lambda_handler(event, context):
    print(event)

    return {
        'body': json.dumps(event, sort_keys = True, indent = 4),
        'statusCode': 200
    }
