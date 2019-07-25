# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :distributed_registry,
  quorum: 1,
  libcluster_ec2_config: [
    ec2_tagname: "aws:autoscaling:groupName",
    polling_interval: 60_000
  ]
