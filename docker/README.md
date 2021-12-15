### 镜像构建命令
```
sudo bash docker/image_build.sh
please enter device (cuda10.1|cuda10.2):" cuda10.1
please enter type (build|develop|runtime):" build
```

### 镜像启动命令
```
docker run -d \
       --name modelbox \
       --security-opt seccomp=unconfined \
       --tmpfs /tmp \
       --tmpfs /run \
       -tmpfs /run/lock \
       -v /sys/fs/cgroup:/sys/fs/cgroup:ro \
       -t modelbox/modelbox_cuda102_runtime:latest
```

### 查看日志
```
docker exec modelbox journalctl
or
docker exec modelbox journalctl -f
```
