tf_init:
	terraform init

tf_lint:
	terraform fmt -recursive -check && \
	  tfsec . # brew install tfsec

tf_apply_dev: tf_lint
	TF_WORKSPACE=dev terraform apply

tf_apply_prod: tf_lint
	TF_WORKSPACE=prod terraform apply

tf_destroy_dev:
	TF_WORKSPACE=dev terraform destroy

tf_destroy_prod:
	TF_WORKSPACE=prod terraform destroy
