FROM jenkins/jenkins:lts-jdk21

# Skip the setup wizard — JCasC handles configuration
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Copy JCasC configuration
ENV CASC_JENKINS_CONFIG=/var/jenkins_home/casc.yaml
COPY jenkins.yaml /usr/share/jenkins/ref/casc.yaml
