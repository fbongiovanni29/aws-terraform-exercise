tf_init:
			terraform init

tf_lint:
			terraform fmt -recursive -check && \
					tfsec . # brew install tfsec

tf_apply: tf_lint
			terraform apply
