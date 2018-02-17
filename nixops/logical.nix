let

  tech-test = import ../.;

  slaveService = {pkgs, ...}: {
    systemd.services.tech-test = {
      description = "IOHK Technical Test Program";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      path = [ pkgs.nettools pkgs.gawk ];
      script = ''
        export IP_ADDRESS=$(ifconfig eth0 | grep 'inet ' | awk '{print $2}')
        ${tech-test}/bin/tech-test $IP_ADDRESS 8080 slave
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = 3;
      };
    };
  };

  node = master:
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ tech-test ];

      environment.variables = {
        TERM = "vt100";
      };

      programs.ssh.startAgent = true;

      # Enable UDP Multicast and open 8080 for node
      networking.firewall = {
        allowedTCPPorts = [ 22 8080 ];
        extraCommands = ''
          iptables -A nixos-fw -d 224.0.0.0/4 -j nixos-fw-accept
        '';
      };

      system.stateVersion = "17.09";
    } // (if master then {} else slaveService { inherit pkgs; });

in
{
  network.description = "IOHK Technical Test";

  node1 = node true;
  node2 = node false;
}
