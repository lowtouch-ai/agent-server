FROM appz/postgres:15.1

MAINTAINER Sreedevi Junu
ADD scripts/postgres-contents /appz/scripts/postgres-contents
COPY webapps/ /tmp/ 
RUN for file in /tmp/*.zip; \
do \
        zip_name="$(basename -- "$file")" \
        && echo "zip name is "$zip_name"" \
        && file_name="${zip_name%.*}" \
        && echo "sub-folder  name is "$file_name"" \
        && if [ -f "$file" ] ; then \
              dest_folder="$(uuidgen)"  \
              && echo "Creating Destination folder:  "$dest_folder"" \
              && mkdir -v  /tmp/"$dest_folder" \
              && unzip   /tmp/"$file_name".zip  -d  /tmp/"$dest_folder" \
              && chmod  -Rv  a+x  /tmp/"$dest_folder/$file_name"  \
              && cp -rv /tmp/$dest_folder/$file_name/*  /appz/scripts/postgres-contents \
              && rm -rfv /tmp/$dest_folder \
              && rm -rfv /tmp/"$zip_name" \
        ;  else \
              echo "zip file not found" \
       ;   fi   \
;done

ADD scripts/postgres_master.sh /appz/scripts/postgres_master.sh
ADD scripts/start.sh /appz/scripts/
RUN chmod +x /appz/scripts/start.sh
RUN chmod 0770 /appz/scripts/postgres_master.sh
ADD supervisor/ /etc/supervisor/conf.d/

