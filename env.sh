#!/bin/bash
set -e

function error()
{
	echo "------------Failed ---------------"
	echo "$1"
	echo "----------------------------------"
	exit 1
}

function tool_download()
{
	# Download KIND
	wget -O kind "https://github.com/kubernetes-sigs/kind/releases/download/v0.18.0/kind-linux-amd64"
	# Download Kubectl
	wget -O kubectl "https://dl.k8s.io/release/v1.26.0/bin/linux/amd64/kubectl"

	if sha256sum -c SHA256SUMS; then
		sudo install -m 755 kind /usr/local/bin/kind
		sudo install -m 755 kubectl /usr/local/bin/kubectl
		kind version
		kubectl version --client=true
	else
		error "Download fail, sha256 mismatch"
	fi
	# Download jq
	sudo apt-get update -y
	sudo apt-get install -y jq

        # Instasll Helm
	curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

	rm -f kind
	rm -f kubectl

	curl -sS https://webinstall.dev/k9s | bash
	source ~/.config/envman/PATH.env
        (
          set -x; cd "$(mktemp -d)" &&
          OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
          ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
          KREW="krew-${OS}_${ARCH}" &&
          curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
          tar zxvf "${KREW}.tar.gz" &&
          ./"${KREW}" install krew
        )
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    echo 'export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"' >> ~/.bashrc
    echo 'source ~/.config/envman/PATH.env' >> ~/.bashrc
}

function clean()
{
	sudo rm -f /usr/local/bin/kind
	sudo rm -f /usr/local/bin/kubectl
}

function create_kind()
{
	if kind get kubeconfig --name k8slab > /dev/null 2>&1 ; then
		echo "cluster is up, please delete first if you want to recreate it."
	else
		kind create cluster --name "k8slab" --config config.yaml
	fi

	kubectl get nodes
}

function delete_kind()
{
	kind delete cluster --name k8slab

	kind get clusters
}

function verify_k8s()
{
	kubectl apply -f test/ingress-nginx || error "Failed to deploy ingress"
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=90s
    sleep 20
	kubectl apply -f test || error "Failed to deploy application"
	kubectl wait deployment/hwchiu-deployment --for=condition=available --timeout=5m

	number_of_sts=$(kubectl get statefulsets web -o jsonpath='{.spec.replicas}')
	echo $number_of_sts
	start_time=$(date +%s)
	timeout=240
	while true; do
		if [[ $number_of_sts == $(kubectl get pods --selector app=nginx | grep Running | wc -l) ]]; then
			echo "condition met"
			break
		fi
		current_time=$(date +%s)
		elapsed_time=$((current_time - start_time))
		if [ $elapsed_time -gt $timeout ]; then
			error "Error: Timeout exceeded for statefulset waiting"
		fi
		echo "StatefulSet not ready, sleep 5s"
		sleep 5
	done

	kubectl cp test/index.html web-0:/usr/share/nginx/html/
	kubectl cp test/index.html web-1:/usr/share/nginx/html/
	kubectl cp test/index.html web-2:/usr/share/nginx/html/

	echo "Verify Network Access, NodrPort"
	curl -s localhost:8080 | grep "nginx test"
	echo "Verify Network Access, Ingress"
	kubectl wait --namespace ingress-nginx \
		--for=condition=ready pod \
		--selector=app.kubernetes.io/component=controller \
		--timeout=90s
	curl -s myserver.hwchiu.com| grep "nginx test"

	echo "Removing testing applications"
	kubectl delete -Rf test
	kubectl delete pvc --all
	echo "-------------------------------------"
	echo "---- Pass Cluster Verification ------"
	echo "-------------------------------------"
}

if [[ "$1" == "install" ]]; then
	echo "Installing reqired files"
	tool_download
elif [[ "$1" == "create" ]]; then
	echo "Creating KIND cluster k8slab"
	create_kind
elif [[ "$1" == "delete" ]]; then
	echo "Deleting KIND cluster k8slab"
	delete_kind
elif [[ "$1" == "verify" ]]; then
	echo "Verify cluster setup"
	verify_k8s
elif [[ "$1" == "clean" ]]; then
	echo "Remove installed tools"
	clean
else
	echo "Usage:"
	echo "  $0 install -- Download needed tools and env setup"
	echo "  $0 create -- setup a KIND cluster"
	echo "  $0 delete -- delete a KIND cluster"
	echo "  $0 verify -- deploy testing application to verify basic components"
	echo "  $0 clean -- clean environment, tools, config...etc"
	exit 1
fi
