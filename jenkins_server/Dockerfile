FROM jenkins/jenkins:lts-jdk21

# Skip the setup wizard — JCasC handles configuration
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false"

# Install plugins
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# JCasC config lives in the image, NOT in the volume.
# Files under /usr/share/jenkins/ref/ are only seeded into JENKINS_HOME on first
# boot, so a casc.yaml placed there goes stale as soon as the volume exists.
# Reading it straight from the image keeps the repo the single source of truth.
COPY jenkins.yaml /usr/local/casc/casc.yaml
ENV CASC_JENKINS_CONFIG=/usr/local/casc/casc.yaml
