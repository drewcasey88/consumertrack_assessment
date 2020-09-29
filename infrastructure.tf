provider "aws" {
    region = "${var.region}"
}

resource "aws_vpc" "sbx" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  
  tags = {
    Name = "SBX"
  }
}

resource "aws_subnet" "public_us_east_1a" {
  vpc_id     = "${aws_vpc.sbx.id}"
  cidr_block = "10.0.0.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "Public Subnet us-east-1a"
  }
}

resource "aws_subnet" "public_us_east_1b" {
  vpc_id     = "${aws_vpc.sbx.id}"
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "Public Subnet us-east-1b"
  }
}

resource "aws_subnet" "public_us_east_1c" {
  vpc_id     = "${aws_vpc.sbx.id}"
  cidr_block = "10.0.2.0/24"
  availability_zone = "us-east-1c"

  tags = {
    Name = "Public Subnet us-east-1c"
  }
}

resource "aws_internet_gateway" "sbx_igw" {
  vpc_id = "${aws_vpc.sbx.id}"

  tags = {
    Name = "SBX - Internet Gateway"
  }
}

resource "aws_route_table" "sbx_public" {
    vpc_id = "${aws_vpc.sbx.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.sbx_igw.id}"
    }

    tags = {
        Name = "Public Subnets Route Table for SBX"
    }
}

resource "aws_route_table_association" "sbx_us_east_1a_public" {
    subnet_id = "${aws_subnet.public_us_east_1a.id}"
    route_table_id = "${aws_route_table.sbx_public.id}"
}

resource "aws_route_table_association" "sbx_us_east_1b_public" {
    subnet_id = "${aws_subnet.public_us_east_1b.id}"
    route_table_id = "${aws_route_table.sbx_public.id}"
}

resource "aws_route_table_association" "sbx_us_east_1c_public" {
    subnet_id = "${aws_subnet.public_us_east_1c.id}"
    route_table_id = "${aws_route_table.sbx_public.id}"
}

resource "aws_security_group" "allow_http" {
  name        = "allow_http"
  description = "HTTP inbound"
  vpc_id = "${aws_vpc.sbx.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "HTTP-SG"
  }
}

resource "aws_key_pair" "deploy" {
  key_name   = "terraform"
  public_key = "ssh-rsa "
}

resource "aws_launch_configuration" "web" {
  name_prefix = "web-"

  image_id = "ami-00514a528eadbc95b" 
  instance_type = "t2.micro"
  key_name = "terraform"

  security_groups = ["${aws_security_group.allow_http.id}"]
  associate_public_ip_address = true

  user_data = <<USER_DATA
#!/bin/bash
yum update
yum -y install nginx
echo -e "instance_id = $(curl http://169.254.169.254/latest/meta-data/instance-id)\n" > /usr/share/nginx/html/index.html
echo -e "instance_type = $(curl http://169.254.169.254/latest/meta-data/instance-type)\n" >> /usr/share/nginx/html/index.html
echo -e "private_ip = $(curl http://169.254.169.254/latest/meta-data/local-ipv4)\n" >> /usr/share/nginx/html/index.html
echo -e "availability_zone = $(curl http://169.254.169.254/latest/meta-data/placement/availability-zone)\n" >> /usr/share/nginx/html/index.html
echo -e "ami_id = $(curl http://169.254.169.254/latest/meta-data/ami-id)" >> /usr/share/nginx/html/index.html
chkconfig nginx on
service nginx start
  USER_DATA

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "elb_http" {
  name        = "elb_http"
  description = "Allow HTTP traffic from ELB"
  vpc_id = "${aws_vpc.sbx.id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Name = "Allow HTTP through ELB Security Group"
  }
}

resource "aws_elb" "web_elb" {
  name = "web-elb"
  security_groups = [
    "${aws_security_group.elb_http.id}"
  ]
  subnets = [
    "${aws_subnet.public_us_east_1a.id}",
    "${aws_subnet.public_us_east_1b.id}",
    "${aws_subnet.public_us_east_1c.id}"
  ]
  cross_zone_load_balancing   = true
  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    interval = 30
    target = "HTTP:80/"
  }
  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = "80"
    instance_protocol = "http"
  }
}

resource "aws_autoscaling_group" "web" {
  name = "${aws_launch_configuration.web.name}-asg"

  min_size             = 3
  desired_capacity     = 3
  max_size             = 4

  health_check_type    = "ELB"
  load_balancers= [
    "${aws_elb.web_elb.id}"
  ]

  launch_configuration = "${aws_launch_configuration.web.name}"
 # availability_zones = ["us-east-1a", "us-east-1b", "us-east-1c"]

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupTotalInstances"
  ]

  metrics_granularity="1Minute"

  vpc_zone_identifier  = [
    "${aws_subnet.public_us_east_1a.id}",
    "${aws_subnet.public_us_east_1b.id}",
    "${aws_subnet.public_us_east_1c.id}"
  ]

  # Required to redeploy without an outage.
  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "web"
    propagate_at_launch = true
  }
}

output "ELB_IP" {
  value = "${aws_elb.web_elb.dns_name}"
}

resource "aws_autoscaling_policy" "web_policy_up" {
  name = "web_policy_up"
  scaling_adjustment = 1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.web.name}"
}

resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_up" {
  alarm_name = "web_cpu_alarm_up"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "60"

  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.web.name}"
  }

  alarm_description = "CPU"
  alarm_actions = ["${aws_autoscaling_policy.web_policy_up.arn}"]
}

resource "aws_autoscaling_policy" "web_policy_down" {
  name = "web_policy_down"
  scaling_adjustment = -1
  adjustment_type = "ChangeInCapacity"
  cooldown = 300
  autoscaling_group_name = "${aws_autoscaling_group.web.name}"
}

resource "aws_cloudwatch_metric_alarm" "web_cpu_alarm_down" {
  alarm_name = "web_cpu_alarm_down"
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods = "2"
  metric_name = "CPUUtilization"
  namespace = "AWS/EC2"
  period = "120"
  statistic = "Average"
  threshold = "10"

  dimensions = {
    AutoScalingGroupName = "${aws_autoscaling_group.web.name}"
  }

  alarm_description = "CPU"
  alarm_actions = ["${aws_autoscaling_policy.web_policy_down.arn}"]
}
