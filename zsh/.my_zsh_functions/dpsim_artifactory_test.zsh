run_dpsim_artifactory_test() {
  emulate -L zsh

  local image="$1"
  local container_name="$2"
  shift 2 || true

  if [[ -z "$image" || -z "$container_name" || "$#" -eq 0 ]]; then
    echo "usage:"
    echo "  run_dpsim_artifactory_test <image> <container_name> <full dpsim_test.py args...>"
    return 1
  fi

  local sim_bin="/home/cyc/ws0/cyclone/source/cyc_core/datapath/debug/simulation/bin"
  local test_logs="/home/cyc/ws0/cyclone/source/cyc_core/datapath/debug/simulation/test_logs"
  local downloads="${sim_bin}/downloads"

  local vol_base="dpsim_dev_${container_name}"
  local vol_1="${vol_base}_1"
  local vol_2="${vol_base}_2"
  local vol_3="${vol_base}_3"

  mkdir -p "$test_logs" "$downloads" || return 1
  chmod 777 "$test_logs" "$downloads" || return 1

  docker pull "$image" || return 1

  docker volume create --driver local "$vol_base" >/dev/null || return 1
  docker volume create --driver local "$vol_1" >/dev/null || return 1
  docker volume create --driver local "$vol_2" >/dev/null || return 1
  docker volume create --driver local "$vol_3" >/dev/null || return 1

  local dpsim_cmd="./dpsim_test.py ${(j: :)${(q)@}}"

  docker run --rm --name "$container_name" \
    --pid=host \
    --privileged \
    --net=host \
    --init \
    --memory=10g \
    --shm-size=2g \
    --log-driver=json-file \
    --cap-add=NET_ADMIN \
    -e DPSIM_IDLE_SERVER_IP_ADDRESS=drmcyc-idle_srv.cec.lab.emc.com:8080 \
    -e DPSIM_SSH_PASSWORD=cycpass \
    -e DPSIM_DEVELOPER_MODE=false \
    -e DOCKER_IMAGE_VERSION="$image" \
    -e DOCKER_INSTANCE_NAME="$container_name" \
    -e DOCKER_LOCAL_EXECUTION_DIRECTORY="$sim_bin" \
    -e 'dp_env="dpsim"' \
    -v /home/cyc/.ssh:/home/cyc/.ssh \
    -v /home/cyc/ws0/cyclone/source:/home/cyc/ws0/cyclone/source \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /tmp/.X11-unix:/tmp/.X11-unix:ro \
    -v /etc/nvme/hostnqn:/etc/nvme/hostnqn:ro \
    -v /etc/nvme/hostid:/etc/nvme/hostid:ro \
    -v /etc/hostname:/etc/real_hostname:ro \
    -v /dev:/dev \
    -v /dev/shm:/dev/shm \
    -v "$vol_base:/tmp" \
    -v /cyc_var/gcov:/cyc_var/gcov \
    -v "$vol_base:/cyc_var" \
    -v "$vol_base:/var/cyclone_dpsim" \
    -v "$vol_1:/var/cyclone_dpsim1" \
    -v "$vol_2:/var/cyclone_dpsim2" \
    -v "$vol_3:/var/cyclone_dpsim3" \
    -v "$test_logs:/opt/cyc_app/debug/simulation/test_logs:rw" \
    -v "$downloads:/opt/cyc_app/debug/simulation/bin/downloads:rw" \
    -w "$sim_bin" \
    "$image" \
    /bin/bash -lc "sudo chown -R cyc:cycg /var; $dpsim_cmd"
}

cleanup_dpsim_artifactory_test() {
  emulate -L zsh
  local container_name="$1"

  if [[ -z "$container_name" ]]; then
    echo "usage: cleanup_dpsim_artifactory_test <container_name>"
    return 1
  fi

  local vol_base="dpsim_dev_${container_name}"
  docker volume rm -f "$vol_base" "$vol_base"_1 "$vol_base"_2 "$vol_base"_3
}
