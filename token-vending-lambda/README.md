# FCS Token Vending Lambda

A token vending machine that sits in front of the CrowdStrike OAuth2 API. The CrowdStrike client secret is held exclusively by this Lambda. Callers — developers and pipelines — receive only a short-lived bearer token that they pass to the FCS CLI via `--falcon-token`.

## Why this approach

The FCS CLI accepts a pre-generated OAuth2 token via `--falcon-token` instead of `--client-id` / `--client-secret`. This lets you decouple secret ownership from scan execution:

| Who | What they have | What they can do |
|---|---|---|
| Security team | Client ID + secret in Secrets Manager | Deploy and manage this Lambda |
| DevOps groups | IAM role with `lambda:InvokeFunction` | Get a token, run scans |
| Developers (local) | AWS SSO session | Get a token, run scans |

Tokens expire in ~30 minutes and carry no persistent value. The secret never leaves the Lambda execution environment.

---

## Architecture

```
Developer / GitHub Actions pipeline
        |
        | AWS IAM (SSO session / OIDC-assumed role)
        v
  Lambda: crowdstrike-fcs-token-vend
        |
        | Lambda execution role only
        v
  Secrets Manager: crowdstrike/fcs-cli
        |
        v
  CrowdStrike OAuth2 /oauth2/token
        |
        v
  Short-lived bearer token returned to caller
        |
        v
  fcs scan image <image> --falcon-token <token>
```

---

## Directory structure

```
token-vending-lambda/
├── lambda/
│   └── handler.py                      # Lambda function
├── iam/
│   ├── execution-role-policy.json      # Attach to the Lambda's execution role
│   └── caller-role-policy.json         # Attach to each team's IAM role
├── .github/
│   └── workflows/
│       └── fcs-scan.yml                # Reference GitHub Actions workflow
├── scripts/
│   └── fcs-scan-local.sh               # Local developer wrapper
└── TESTING.md                          # Step-by-step deployment and validation guide
```

---

## Deployment

For a complete step-by-step walkthrough covering IAM setup, Secrets Manager, Lambda packaging and deployment, and end-to-end validation, see [TESTING.md](TESTING.md).

### 1. Store credentials in Secrets Manager

The secret must be a JSON object with `client_id` and `client_secret` keys:

```shell
aws secretsmanager create-secret \
  --name crowdstrike/fcs-cli \
  --region us-east-1 \
  --secret-string '{"client_id":"<YOUR_CLIENT_ID>","client_secret":"<YOUR_CLIENT_SECRET>"}'
```

Required API client scopes (created in **Falcon console > Support and resources > Resources and tools > API clients and keys**):

| Scope | Permission |
|---|---|
| Cloud Security Tools Download | Read |
| Falcon Container CLI | Read / Write |
| Falcon Container Image | Read / Write |

### 2. Create the Lambda execution role

1. Create an IAM role with the `lambda.amazonaws.com` trust relationship.
2. Attach `iam/execution-role-policy.json` as an inline policy.
3. Replace `ACCOUNT_ID` in the policy with your AWS account ID.

### 3. Deploy the Lambda

```shell
cd lambda
zip handler.zip handler.py

aws lambda create-function \
  --function-name crowdstrike-fcs-token-vend \
  --runtime python3.12 \
  --handler handler.handler \
  --role arn:aws:iam::ACCOUNT_ID:role/crowdstrike-fcs-token-vend-role \
  --zip-file fileb://handler.zip \
  --environment "Variables={SECRET_ID=crowdstrike/fcs-cli,FALCON_API_URL=https://api.crowdstrike.com}"
```

See [API Base URLs by Region](#api-base-urls-by-region) if your CrowdStrike tenant is not in US-1.

### 4. Grant access per team

For each DevOps group, attach `iam/caller-role-policy.json` to their IAM role. Replace `ACCOUNT_ID`. This is the only permission they need — no Secrets Manager access.

---

## Usage

### Local developers

Prerequisites:
- AWS CLI with an active SSO session or a configured role that has `lambda:InvokeFunction`
- `fcs` CLI installed and on `$PATH`
- `jq` installed

```shell
./scripts/fcs-scan-local.sh myapp:latest
./scripts/fcs-scan-local.sh myapp:latest --upload
./scripts/fcs-scan-local.sh myapp:latest --minimum-severity high --upload
```

Environment variable overrides:

| Variable | Default | Description |
|---|---|---|
| `AWS_REGION` | `us-east-1` | Region where the Lambda is deployed |
| `FALCON_REGION` | `us-1` | CrowdStrike cloud region |
| `LAMBDA_FUNCTION` | `crowdstrike-fcs-token-vend` | Lambda function name |

### GitHub Actions pipelines

See `.github/workflows/fcs-scan.yml` for a complete reference workflow.

The workflow uses GitHub's OIDC provider to assume an IAM role — no secrets are stored in GitHub. The only repository variable required is `FCS_SCAN_ROLE_ARN`, which is the ARN of the team's IAM role.

Key steps:
1. Assume IAM role via OIDC (`aws-actions/configure-aws-credentials`)
2. Invoke the Lambda to get a token (masked immediately with `::add-mask::`)
3. Download the FCS CLI binary using the token
4. Run `fcs scan image` with `--falcon-token`

---

## Audit trail

Every Lambda invocation is logged in CloudTrail under `lambda:InvokeFunction`. The log includes the caller's IAM role ARN, timestamp, and source IP — giving you a per-team, per-run audit trail without any custom logging.

---

## API Base URLs by Region

| CrowdStrike Cloud | API Base URL | `FALCON_REGION` value |
|---|---|---|
| US-1 | https://api.crowdstrike.com | `us-1` |
| US-2 | https://api.us-2.crowdstrike.com | `us-2` |
| EU-1 | https://api.eu-1.crowdstrike.com | `eu-1` |
| US-GOV-1 | https://api.laggar.gcw.crowdstrike.com | `us-gov-1` |
| US-GOV-2 | https://api.us-gov-2.crowdstrike.mil | `us-gov-2` |
