# INSTANCES #

resource "google_compute_instance" "mail1" {
  project = "mail-test-419119"
  name     = "mail1"
  hostname = "mail1.gcp.barisano.cloud"
  boot_disk {
    initialize_params {
      image = var.instance_image
    }
  }
  machine_type = var.instance_type
  zone         = var.gcp_zone
  network_interface {
    network = "projects/mail-test-419119/global/networks/default"
    access_config {

    }
  }
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
    sudo echo '[smtp.sendgrid.net]:2525 apikey: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' >> /root/sasl_passwd
    sudo postmap /root/sasl_passwd
    sudo rm /root/sasl_passwd
    sudo chmod 600 /root/sasl_passwd.db
    sudo mv /root/sasl_passwd.db /etc/postfix/
    sudo echo 'address {
    email-domain barisano.cloud;
    };' | sudo tee -a /root/mailutils.conf
    sudo mv /root/mailutils.conf /etc/
    sudo echo barisano.cloud | sudo tee /etc/mailname
    sudo touch /var/mail/jbarisan
    sudo chown josh:sudo /var/mail/jbarisan
    sudo useradd josh
    sudo usermod -aG sudo josh
    sudo touch /var/mail/josh
    sudo chown josh:sudo /var/mail/josh
    sudo /etc/init.d/postfix restart
    sudo apt -y install mailutils
    EOF
  }
}