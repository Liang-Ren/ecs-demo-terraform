# ECS Demo Terraform Deployment

A complete, reproducible AWS infrastructure example using **Terraform**, **ECS Fargate**, **Application Load Balancer**, **ECR**, **CloudWatch Logs**, **Container Insights**, **CloudWatch Alarms**, **GuardDuty**, and **Security Hub**.

This project demonstrates how to deploy a fully managed serverless container workload on AWS using Infrastructure-as-Code, along with integrated observability and security monitoring.

---

## 📦 Features

* **ECS Fargate Service** (no EC2 required)
* **Application Load Balancer** with health checks
* **ECR** container image hosting
* **CloudWatch Logs + Metrics + Container Insights**
* **Custom log metric filters** and CloudWatch Alarms
* **SNS alarm notifications**
* **GuardDuty enabled** for threat detection
* **Security Hub enabled** with foundational best practices
* Fully automated provisioning & teardown via **Terraform**

---

## 🏗 Architecture

```
                      +-----------------------------+
                      |        GitHub Repo          |
                      |  ecs-demo-terraform (TF)    |
                      +--------------+--------------+
                                     |
                                     v
                         terraform apply
                                     |
        -----------------------------------------------------------------
                                     |
                                     v
+-----------------------+       +-----------------------------------------+
|      Amazon ECR       |       |           Amazon ECS Cluster            |
| (ecs-demo:latest img) | ----> |  Fargate Tasks (2+) running container   |
+-----------------------+       |  Task Definition (CPU/MEM/Ports/Logs)   |
                                +---------------------+-------------------+
                                                      |
+------------------------------+                      v
|       Application LB         | <-------------- Target Group (8080)
|  http://<alb-dns-name>       |
|  distributes traffic          |
+---------------+--------------+
                |
                v
          End-user Browser
```

Monitoring & Security:

```
ECS Logs --> CloudWatch Log Group --> Metric Filter --> CW Alarm --> SNS Topic
ECS Metrics --> CloudWatch (Container Insights)

GuardDuty Findings --> EventBridge Rule --> SNS Topic
Security Hub <-- aggregated security findings
```

---

## 📋 Prerequisites

| Requirement     | Description                                                       |
| --------------- | ----------------------------------------------------------------- |
| AWS Account     | With permissions to create IAM, ECS, ECR, ALB, CW, SNS            |
| AWS CLI         | Configured with credentials                                       |
| Terraform ≥ 1.5 | Required to apply the IaC stack                                   |
| Docker          | To build and push the container image                             |
| Region          | This demo assumes **us-east-1** (you can change via variables.tf) |

---

## 🚀 Deployment Steps (From Zero to Working Web Page)

### **1. Build the sample application (optional)**

If you already have a working container image, skip to step 2.

Example Node.js app:

```
Hello from ECS demo! 🚢
```

---

### **2. Build and Push Image to ECR**

```bash
AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws ecr get-login-password --region $AWS_REGION \
  | docker login \
    --username AWS \
    --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

docker build -t ecs-demo:latest .
docker tag ecs-demo:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ecs-demo:latest
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/ecs-demo:latest
```

Copy the final image URI for Terraform:

```
123456789012.dkr.ecr.us-east-1.amazonaws.com/ecs-demo:latest
```

---

### **3. Initialize Terraform**

```bash
cd ecs-demo-terraform
terraform init
```

---

### **4. Run Terraform Plan**

```bash
terraform plan \
  -var="region=us-east-1" \
  -var="ecs_demo_image=<your-ecr-image-uri>"
```

---

### **5. Deploy Infrastructure**

```bash
terraform apply \
  -var="region=us-east-1" \
  -var="ecs_demo_image=<your-ecr-image-uri>"
```

Confirm with `yes`.

Terraform will create:

* ECS Cluster, Service, Task Definition
* ALB + Target Group
* Security Groups
* CloudWatch logs, metric filters, alarms
* SNS topic
* GuardDuty detector
* Security Hub standard subscription

When complete, Terraform outputs:

```
alb_dns_name = "ecs-demo-alb-xxxxxxxx.us-east-1.elb.amazonaws.com"
```

---

### **6. Validate the Deployment**

#### **6.1 Open the application in a browser**

```
http://ecs-demo-alb-xxxxxxxx.us-east-1.elb.amazonaws.com
```

You should see:

```
Hello from ECS demo! 🚢
```

#### **6.2 Validate ECS**

ECS Console → Clusters → `ecs-demo-cluster`

* Service: `ecs-demo-service`
* Running Tasks: 2

#### **6.3 Validate Target Group**

EC2 Console → Target Groups → `ecs-demo-tg`

* Health status: **healthy**

#### **6.4 Validate CloudWatch Logs**

CloudWatch → Log Groups → `/ecs/ecs-demo`

* Container stdout visible

#### **6.5 Validate Metrics & Alarms**

CloudWatch → Alarms:

* ECS-Demo-CPU-High
* ECS-Demo-High-Error-Rate

#### **6.6 Validate GuardDuty**

GuardDuty → Findings
(or use “Generate sample findings”)

#### **6.7 Validate Security Hub**

Security Hub → Dashboard

* Findings from GuardDuty aggregated
* AWS Foundational Security Best Practices enabled

---

## 🛡 Security & Observability Integrations

### ✔ CloudWatch Logs

All container logs are streamed into:

```
/ecs/ecs-demo
```

### ✔ Container Insights

ECS Cluster metrics:

* CPUUtilization
* MemoryUtilization
* Network I/O

### ✔ Custom Metric Filters

Matches `"ERROR"` log lines → emits custom metric → triggers CloudWatch Alarm.

### ✔ CloudWatch Alarms

Two alarms included:

| Alarm                        | Purpose                    |
| ---------------------------- | -------------------------- |
| **ECS-Demo-CPU-High**        | Detect abnormal CPU spikes |
| **ECS-Demo-High-Error-Rate** | Detect log error bursts    |

Both alarms publish to the SNS topic:

```
ecs-security-alerts
```

### ✔ GuardDuty Detection

Threat detection is enabled:

* IAM anomalies
* Malicious IP communication
* Reconnaissance
* Crypto-mining behavior
* Unauthorized API calls

### ✔ Security Hub

Security Hub aggregates and normalizes security findings.

Enabled standard:

* AWS Foundational Security Best Practices v1.0.0

---

## 🧹 Cleanup

To remove all infrastructure:

```bash
terraform destroy \
  -var="region=us-east-1" \
  -var="ecs_demo_image=<your-ecr-image-uri>"
```

Confirm with `yes`.

Then manually delete your ECR repository (optional):

```
ecs-demo
```

---

## 🤝 Contributing

Pull requests and issues are welcome.

---

## 📄 License

MIT (or update based on your preference)
