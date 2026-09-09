{
  lib,
  pkgs,
  ...
} @ inputs: let
  images = import ./images.nix inputs;
  qemu = "${pkgs.qemu_kvm}/bin/qemu-kvm";
in
  lib.mapAttrs (ros_version: image:
    pkgs.writeShellApplication {
      name = "vm-${ros_version}";
      text = ''
        VM_IMAGE_FILE=$(ls ${image}/*.img)

        ${qemu} \
          -m 256 \
          -machine type=pc \
          -nographic \
          -serial mon:stdio \
          -drive "file=''${VM_IMAGE_FILE},format=raw,id=hd0,snapshot=on" \
          -netdev "user,id=net0,hostfwd=tcp::''${VM_SSH_PORT:-2222}-:22" \
          -device virtio-net-pci,netdev=net0 \
          "''${@}"
      '';
    })
  images
