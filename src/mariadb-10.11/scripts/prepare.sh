cd ${1:-/appz/server/}
for dir in /tmp/*/ ; do
    echo "preparing folder contents of "$dir"..."
    if [ -d "$dir" ]; then
        echo $dir" is a valid folder"
        cp -rv $dir/*  ${1:-/appz/server/}
        rm -rf $dir
    fi
done
for file in /tmp/*.zip; \
do \
    echo "preparing "$file"..."
    zip_name="$(basename -- "$file")" \
    && echo "zip name is "$zip_name"" \
    && file_name="${zip_name%.*}" \
    && echo "sub-folder  name is "$file_name"" \
    && if [ -f "$file" ] ; then \
            dest_folder="$(uuidgen)"  \
            && echo "Creating Destination folder:  "$dest_folder"" \
            && mkdir -v  /tmp/"$dest_folder" \
            && unzip   /tmp/"$file_name".zip -d  /tmp/"$dest_folder" \
            && chmod  -Rv  a+x  /tmp/"$dest_folder/$file_name"  \
            && cp -rv /tmp/$dest_folder/$file_name/*  ${1:-/appz/server/} \
            && rm -rfv /tmp/$dest_folder \
            && rm -rfv /tmp/"$zip_name" \
        ;  else \
            echo "zip file not found" \
    ;   fi   \
;done
