##########################################
# PROVIDERS                              #
##########################################

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}

##########################################
# NETWORK                                #
##########################################

resource "google_compute_global_address" "app" {
  name       = "app-global-static-ip"
  ip_version = "IPV4"
}

resource "google_compute_network" "app" {
  name                    = "app-network"
  auto_create_subnetworks = false
}

resource "google_compute_firewall" "default" {
  name          = "allow-http-traffic"
  network       = google_compute_network.app.id
  source_ranges = ["0.0.0.0/0"]
  allow {
    ports    = ["80", "443", "22", "2525"]
    protocol = "tcp"
  }
  target_tags = ["allow-health-check", "allow-all"]
}

resource "google_compute_subnetwork" "public_subnet1" {
  name          = "sub-network"
  ip_cidr_range = var.vpc_public_subnet1_cidr_block
  network       = google_compute_network.app.id
}

##########################################
# DNS                                    #
##########################################

resource "google_dns_record_set" "app-lb" {
  name         = "terraform-test.gcp.barisano.cloud."
  managed_zone = var.dns_managed_zone
  type         = "A"
  ttl          = 300
  rrdatas = [
    google_compute_global_address.app.address
  ]
}

##########################################
# VMs                                    #
##########################################

# Template
resource "google_compute_instance_template" "app" {
  name_prefix = "nginx-vm-template-"
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    device_name  = "persistent-disk-0"
    mode         = "READ_WRITE"
    type         = "PERSISTENT"
  }
  machine_type = var.instance_type
  metadata = {
    startup-script = <<-EOF
    #!/bin/bash
    sudo apt-get install -y nginx
    NAME=$(curl -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")
    sudo echo '<html><head><title>Taco Team Server</title></head><body style=\"background-color:#1F778D\"><p style=\"text-align: center;\"><span style=\"color:#FFFFFF;\"><span style=\"font-size:28px;\">You did it! Have a &#127790;</span></span></p><p>' | sudo tee /var/www/html/index.html
    sudo echo $NAME | sudo tee -a /var/www/html/index.html
    sudo echo '</p></body></html>' | sudo tee -a /var/www/html/index.html
    sudo systemctl restart nginx
    EOF
  }
  network_interface {
    network    = google_compute_network.app.name
    subnetwork = google_compute_subnetwork.public_subnet1.name
    access_config {
      # Each instance will get an ip which can be used for package managers
    }
  }
  region = var.gcp_region
  tags   = ["allow-health-check"]
  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_instance_template" "mail" {
  name_prefix = "nginx-vm-template-"
  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete  = true
    boot         = true
    device_name  = "persistent-disk-0"
    mode         = "READ_WRITE"
    type         = "PERSISTENT"
  }
  machine_type = "e2-micro"
  metadata = {
    startup-script = <<-EOF
    #!/bin/bash
    apt update && apt -y install postfix libsasl2-modules
    sudo sed -i 's/default_transport = error/# default_transport = error/g' /etc/postfix/main.cf
    sudo sed -i 's/relay_transport = error/# relay_transport = error/g' /etc/postfix/main.cf
    sudo sed -i 's/relayhost =/relayhost = [smtp.sendgrid.net]:2525/g' /etc/postfix/main.cf
    sudo sed -i 's/smtp_tls_security_level=may/smtp_tls_security_level = encrypt/g' /etc/postfix/main.cf
    sudo echo 'smtp_sasl_auth_enable = yes
    smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
    header_size_limit = 4096000
    smtp_sasl_security_options = noanonymous' | sudo tee -a /etc/postfix/main.cf
    sudo echo [smtp.sendgrid.net]:2525 apikey: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 >> /root/sasl_passwd
    sudo postmap /root/sasl_passwd
    sudo rm /root/sasl_passwd
    sudo chmod 600 /root/sasl_passwd.db
    sudo mv /root/sasl_passwd.db /etc/postfix/
    sudo echo 'address {
    email-domain barisano.cloud;
    };' | sudo tee -a /root/mailutils.conf
    sudo mv /root/mailutils.conf /etc/
    sudo /etc/init.d/postfix restart
    sudo apt -y install mailutils
    EOF
  }
  network_interface {
    network    = google_compute_network.app.name
    subnetwork = google_compute_subnetwork.public_subnet1.name
    access_config {
      # Each instance will get an ip which can be used for package managers
    }
  }
  region = var.gcp_region
  tags   = ["allow-health-check"]
  lifecycle {
    create_before_destroy = true
  }
}

# Instance Group
resource "google_compute_region_instance_group_manager" "default" {
  name = "managed-instance-group"
  region = "us-east1"
  distribution_policy_zones = ["us-east1-b", "us-east1-c", "us-east1-d"]
  named_port {
    name = "http"
    port = 80
  }
  version {
    instance_template = google_compute_instance_template.app.id
  }
  base_instance_name = "nginx"
  target_size        = 2
}

resource "google_compute_health_check" "app" {
  name               = "http-basic-check"
  check_interval_sec = 5
  healthy_threshold  = 2
  http_health_check {
    port               = 80
    port_specification = "USE_FIXED_PORT"
    proxy_header       = "NONE"
    request_path       = "/"
  }
  timeout_sec         = 5
  unhealthy_threshold = 2
}

resource "google_compute_backend_service" "app" {
  name                            = "app-backend-service"
  connection_draining_timeout_sec = 0
  health_checks                   = [google_compute_health_check.app.id]
  load_balancing_scheme           = "EXTERNAL"
  port_name                       = "http"
  protocol                        = "HTTP"
  session_affinity                = "NONE"
  timeout_sec                     = 30
  backend {
    group           = google_compute_region_instance_group_manager.default.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

##########################################
# LOAD BALANCER                          #
##########################################

# forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = "taco-team-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.app.id
}

# http proxy
resource "google_compute_target_http_proxy" "default" {
  name    = "taco-team-target-http-proxy"
  url_map = google_compute_url_map.default.id
}

# url map
resource "google_compute_url_map" "default" {
  name            = "taco-team-elb"
  default_service = google_compute_backend_service.app.id
}
