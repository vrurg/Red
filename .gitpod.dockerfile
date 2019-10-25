FROM gitpod/workspace-full
USER root
RUN apt-get update                                                 \
  && apt-get install -y build-essential uuid-dev sqlite3 perl6 vim \
  && zef install --/test App::Mi6
USER gitpod
