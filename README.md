# ConsumerTrack

This is a terraform plan which will create a new vpc and necessary infrastructure to host an autoscaling group with a minimum of 3 instances behind an elb. When the elb dns is reached, a few details of the responding server will appear via NGINX. (All AWS resources will be created in US-EAST-1)

# prerequisites
An ssh key pair. Directions on generating one can be found here: https://www.ssh.com/ssh/keygen/

It is assumed that you have aws cli installed and configured with admin priviliges. (~/.aws/credentials) 
See installation and config here: https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-install.html

It is also assumes that you have Terraform installed. 
See installation and config here: https://learn.hashicorp.com/tutorials/terraform/install-cli

# Usage

From the root directory, simply perform: 
```terraform init```
```terraform plan```
```terraform apply -var="public_key=<your_public_key_here"```
type ```yes``` when prompted

The elb dns will output like so:
```ELB_IP = web-elb-1476806189.us-east-1.elb.amazonaws.com```
Copy and paste the address into your browser and refresh to see the different instance information as each is hit from the elb.
