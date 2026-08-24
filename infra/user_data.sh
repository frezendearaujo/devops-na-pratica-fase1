#!/bin/bash
set -euxo pipefail

# Bootstrap da instancia: instala o runtime de containers, obtem o codigo da
# aplicacao a partir do repositorio publico e sobe o container.
dnf update -y
dnf install -y docker git

systemctl enable --now docker

git clone https://github.com/frezendearaujo/devops-na-pratica-fase1.git /opt/app
cd /opt/app

docker build -t tasks-api .
docker run -d --name tasks-api --restart always -p 80:3000 tasks-api
