# Terraform Static Web Site

> Terraform to deploy a static web site ami for code exercise. After applying dev it's available at https://dev.fbongiovanni.click and prod is available https://fbongiovanni.click

## Dependencies

#### [tfsec](https://github.com/aquasecurity/tfsec)
```
brew install tfsec
```

#### [terraform](https://www.terraform.io/)
```
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

## Apply Changes

#### Dev
```
make tf_init
make tf_apply_dev
```
#### Prod
```
make tf_init
make tf_apply_prod
```
## Running in Concourse
#### Prequisites
[fly](https://github.com/concourse/concourse/releases)
```
docker compose up -d
fly -t terraform login -c http://localhost:8080 -u me -p <PASSWORD HERE>
fly -t terraform set-pipeline -c terraform-pipeline.yaml -p terraform-pipeline-dev -v access-key=<AWS_ACCESS_KEY_ID> -v secret-key=<AWS_SECRET_ACCESS_KEY> -v terraform-workspace=dev
fly -t terraform set-pipeline -c terraform-pipeline.yaml -p terraform-pipeline-prod -v access-key=<AWS_ACCESS_KEY_ID> -v secret-key=<AWS_SECRET_ACCESS_KEY> -v terraform-workspace=prod

* Navigate to http://localhost:8080/teams/main/pipelines/terraform-pipeline-<ENVIRONMENT> and trigger pipeline
```
## Bootstrap
Bootstrap resources live in `./bootstrap/` for now it is just the bucket that stores the remote state.

