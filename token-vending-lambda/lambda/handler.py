import json
import boto3
import urllib.request
import urllib.parse
import os

REGION = os.environ.get("AWS_REGION", "us-east-1")
SECRET_ID = os.environ.get("SECRET_ID", "crowdstrike/fcs-cli")
FALCON_API_URL = os.environ.get("FALCON_API_URL", "https://api.crowdstrike.com")


def handler(event, context):
    """
    Token vending machine for CrowdStrike FCS CLI.

    Fetches the CrowdStrike API client credentials from Secrets Manager,
    exchanges them for a short-lived OAuth2 bearer token, and returns
    that token to the caller.

    The caller never sees the client secret — only the Lambda execution
    role has Secrets Manager access. Callers only need lambda:InvokeFunction.
    """
    token, expires_in = _get_falcon_token()

    return {
        "statusCode": 200,
        "body": json.dumps({
            "token": token,
            "expires_in": expires_in,
        }),
    }


def _get_falcon_token():
    secret = _get_secret()
    client_id = secret["client_id"]
    client_secret = secret["client_secret"]

    payload = urllib.parse.urlencode({
        "client_id": client_id,
        "client_secret": client_secret,
    }).encode()

    req = urllib.request.Request(
        f"{FALCON_API_URL}/oauth2/token",
        data=payload,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=10) as resp:
        body = json.loads(resp.read())

    if "access_token" not in body:
        raise RuntimeError(f"CrowdStrike OAuth2 did not return an access_token: {body}")

    return body["access_token"], body.get("expires_in", 1800)


def _get_secret():
    sm = boto3.client("secretsmanager", region_name=REGION)
    value = sm.get_secret_value(SecretId=SECRET_ID)
    return json.loads(value["SecretString"])
