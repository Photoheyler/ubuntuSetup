docker push labeltool.heinrichstefan.eu/deploy:latest

# NVIDIA als Docker Default Runtime setzen

sudo nvidia-ctk runtime configure --runtime=docker --set-as-default
sudo systemctl restart docker
docker info | grep -i "Default Runtime"
