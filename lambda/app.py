import json

def lambda_handler(event, context):
    print(event)

    return {
        'body': str(json.dumps(event, sort_keys = True, indent = 4))
    }
