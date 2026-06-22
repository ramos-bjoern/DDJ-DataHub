# DDJ-DataHub AWS Deployment — Plan C: CI/CD Pipeline

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub Actions Pipeline die bei jedem Push auf `main` den Stack automatisch auf EC2 deployed — ohne manuelles SSH.

**Architecture:** GitHub Actions verbindet sich per SSM (kein SSH-Port nötig) mit der EC2-Instanz, pullt das Repo und startet den Stack neu. Secrets liegen in GitHub Secrets, nie im Code.

**Tech Stack:** GitHub Actions, AWS SSM Session Manager, Docker Compose

**Voraussetzung:** Plan A und Plan B sind abgeschlossen — Stack läuft auf EC2.

---

## Dateistruktur

```
DDJ-DataHub/
└── .github/
    └── workflows/
        └── deploy.yml    # Deploy-Pipeline
```

---

## Task 1: GitHub Secrets einrichten

- [ ] **Schritt 1: IAM-User für GitHub Actions anlegen**

Auf lokalem Mac (AWS CLI):

```bash
aws iam create-user \
  --user-name ddj-datahub-github-actions \
  --profile rndtech-sso

aws iam create-access-key \
  --user-name ddj-datahub-github-actions \
  --profile rndtech-sso
```

Ausgabe notieren: `AccessKeyId` und `SecretAccessKey`.

- [ ] **Schritt 2: Minimale IAM-Policy für SSM + EC2 anlegen**

```bash
aws iam put-user-policy \
  --user-name ddj-datahub-github-actions \
  --policy-name ssm-deploy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ssm:StartSession",
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation"
        ],
        "Resource": "*"
      },
      {
        "Effect": "Allow",
        "Action": "ec2:DescribeInstances",
        "Resource": "*"
      }
    ]
  }' \
  --profile rndtech-sso
```

- [ ] **Schritt 3: GitHub Secrets setzen**

Im GitHub-Repo unter `Settings → Secrets and variables → Actions → New repository secret`:

| Secret Name | Wert |
|---|---|
| `AWS_ACCESS_KEY_ID` | AccessKeyId aus Schritt 1 |
| `AWS_SECRET_ACCESS_KEY` | SecretAccessKey aus Schritt 1 |
| `AWS_REGION` | `eu-central-1` |
| `EC2_INSTANCE_ID` | Aus `terraform output ec2_instance_id` |

---

## Task 2: GitHub Actions Deploy-Pipeline

**Files:**
- Create: `.github/workflows/deploy.yml`

- [ ] **Schritt 1: Verzeichnis anlegen**

```bash
mkdir -p /Users/b_ramos/Developer/github/ramos-bjoern/DDJ-DataHub/.github/workflows
```

- [ ] **Schritt 2: `.github/workflows/deploy.yml` anlegen**

```yaml
name: Deploy to AWS

on:
  push:
    branches:
      - main
  workflow_dispatch:  # Manueller Trigger über GitHub UI

jobs:
  deploy:
    name: Deploy DDJ-DataHub
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Install SSM plugin
        run: |
          curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
            -o session-manager-plugin.deb
          sudo dpkg -i session-manager-plugin.deb

      - name: Deploy via SSM
        run: |
          aws ssm send-command \
            --instance-ids "${{ secrets.EC2_INSTANCE_ID }}" \
            --document-name "AWS-RunShellScript" \
            --comment "Deploy DDJ-DataHub ${{ github.sha }}" \
            --parameters commands='[
              "cd /opt/ddj-datahub",
              "git pull origin main",
              "docker compose -f docker-compose.yml -f docker-compose.prod.yml pull",
              "docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --remove-orphans",
              "docker compose -f docker-compose.yml -f docker-compose.prod.yml ps"
            ]' \
            --output-s3-bucket-name "" \
            --region "${{ secrets.AWS_REGION }}" \
            --query "Command.CommandId" \
            --output text > /tmp/command_id.txt

          echo "Command ID: $(cat /tmp/command_id.txt)"

      - name: Wait for deploy to complete
        run: |
          COMMAND_ID=$(cat /tmp/command_id.txt)
          echo "Waiting for command $COMMAND_ID..."

          for i in $(seq 1 30); do
            STATUS=$(aws ssm get-command-invocation \
              --command-id "$COMMAND_ID" \
              --instance-id "${{ secrets.EC2_INSTANCE_ID }}" \
              --query "Status" \
              --output text 2>/dev/null || echo "Pending")

            echo "Status: $STATUS (attempt $i/30)"

            if [ "$STATUS" = "Success" ]; then
              echo "✅ Deploy erfolgreich"
              # Output anzeigen
              aws ssm get-command-invocation \
                --command-id "$COMMAND_ID" \
                --instance-id "${{ secrets.EC2_INSTANCE_ID }}" \
                --query "StandardOutputContent" \
                --output text
              exit 0
            elif [ "$STATUS" = "Failed" ] || [ "$STATUS" = "TimedOut" ]; then
              echo "❌ Deploy fehlgeschlagen: $STATUS"
              aws ssm get-command-invocation \
                --command-id "$COMMAND_ID" \
                --instance-id "${{ secrets.EC2_INSTANCE_ID }}" \
                --query "StandardErrorContent" \
                --output text
              exit 1
            fi

            sleep 10
          done

          echo "❌ Timeout nach 5 Minuten"
          exit 1

      - name: Health check
        run: |
          sleep 15
          STATUS=$(curl -s -o /dev/null -w "%{http_code}" https://datahub.rndtech.de/server/health)
          if [ "$STATUS" = "200" ]; then
            echo "✅ Health check passed (HTTP $STATUS)"
          else
            echo "❌ Health check failed (HTTP $STATUS)"
            exit 1
          fi
```

- [ ] **Schritt 3: Committen und Pipeline auslösen**

```bash
git add .github/workflows/deploy.yml
git commit -m "feat(ci): add GitHub Actions deploy pipeline via SSM"
git push origin main
```

- [ ] **Schritt 4: Pipeline in GitHub beobachten**

`https://github.com/ramos-bjoern/DDJ-DataHub/actions` → Pipeline läuft durch.

Erwartete Ausgabe: Alle Steps grün, Health Check HTTP 200.

---

## Self-Review Checkliste

- [ ] GitHub Secrets sind gesetzt (AWS-Keys, EC2-ID)
- [ ] IAM-User hat nur minimale SSM-Rechte (kein Admin)
- [ ] Pipeline läuft bei Push auf `main` automatisch
- [ ] Deploy-Kommando wartet auf Abschluss bevor Health Check
- [ ] Health Check schlägt fehl wenn Stack nicht antwortet
- [ ] Kein SSH-Port (22) muss offen sein
- [ ] Manueller Trigger über `workflow_dispatch` möglich
