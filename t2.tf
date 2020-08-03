provider "aws" {
  region = "ap-south-1"
  profile = "mytejas"
}


resource "aws_security_group" "t2sg" {
  name        = "t2sg"
  description = "Allow HTTP and SSH to ec2"
  vpc_id      = "vpc-2feef347"

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "t2sg"
  }
}


resource "aws_instance" "t2os" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = "mykey"
  security_groups = ["t2sg"]

  tags = {
    Name = "t2os"
  }
}


output "public_ip"{
  value=aws_instance.t2os.public_ip
}


resource "aws_efs_file_system" "t2efs" {
depends_on = [
  aws_instance.t2os
 ]

creation_token = "efs"

  tags = {
    Name = "t2efs"
  }
}


resource "aws_efs_mount_target" "mount_efs" {
depends_on = [
    aws_efs_file_system.t2efs
 ]

file_system_id = aws_efs_file_system.t2efs.id

subnet_id = aws_instance.t2os.subnet_id

security_groups=[aws_security_group.t2sg.id]
}


resource "null_resource" "null1" {

   depends_on = [
       aws_efs_mount_target.mount_efs,
   ]

   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = file("C:/Users/HP/Downloads/mykey.pem")
    host     = aws_instance.t2os.public_ip
  }

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount /dev/xvdh   /var/www/html",
      "sudo rm -rf /var/www/html",
      "sudo git clone https://github.com/Tejas-Gosavi/task2.git /var/www/html"
    ]
   }
}

resource "aws_s3_bucket" "t2s3" {
  depends_on = [
       null_resource.null1,
   ]
  bucket = "myt2s3"
  acl    = "public-read"
  versioning {
          enabled = true
  }
  tags = {
    Name        = "myt2s3"
  }
}


locals {
  s3_origin_id = "S3-${aws_s3_bucket.t2s3.bucket}"
}


resource "aws_s3_bucket_object" "upload" {
   depends_on = [
       aws_s3_bucket.t2s3
   ]
  bucket = aws_s3_bucket.t2s3.bucket
  key    = "tejas.jpeg"
  source = ("C:/Users/HP/Desktop/terra/task2/tejas.jpeg")
}


resource "aws_cloudfront_distribution" "s3_distribution" {

  depends_on = [
       aws_s3_bucket_object.upload,
   ]

  origin {
    domain_name = aws_s3_bucket.t2s3.bucket_domain_name
    origin_id   = local.s3_origin_id
  }


  enabled             = true 

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

    viewer_certificate {
    cloudfront_default_certificate = true
  }
}





resource "null_resource" "null2" {
depends_on = [
     null_resource.null1,
     aws_cloudfront_distribution.s3_distribution,
]

connection {
        type        = "ssh"
    	user        = "ec2-user"
    	private_key = file("C:/Users/HP/Downloads/mykey.pem")
        host     = aws_instance.t2os.public_ip
        }
  
provisioner "remote-exec" {
    inline = [
      "sudo su <<END",
      "echo \" Hey,Tejas Gosavi here!!! <img src='http://${aws_cloudfront_distribution.s3_distribution.domain_name}/${aws_s3_bucket_object.upload.key}' height='300' width='300'>\" >> /var/www/html/my.html",
      "END",
    ]
  }
provisioner "local-exec" {    
      command = "start chrome http://${aws_instance.t2os.public_ip}/my.html"
   }
}