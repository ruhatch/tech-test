let

  region = "eu-west-1";
  zone = "eu-west-1a";

  node = 
    { resources, ... }:
    { deployment.targetEnv = "ec2";
      deployment.ec2.region = region;
      deployment.ec2.zone = zone;
      deployment.ec2.instanceType = "t2.medium";
      deployment.ec2.ebsInitialRootDiskSize = 30;
      deployment.ec2.keyPair = resources.ec2KeyPairs.serverKeyPair;
    };
  
in
{

  node1 = node;
  node2 = node;

  # Provision an EC2 key pair
  resources.ec2KeyPairs.serverKeyPair = {
    inherit region;
  };

}
