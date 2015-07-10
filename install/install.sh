#! /bin/sh
# Führt ein stückweises Update für alle Versionen durch, sofern diese noch
# nicht installiert wurden.

# Basisverzeichnis liegt eins über unserem eigenen Verzeichnis
c_base=$(dirname $(dirname $(readlink -f $0)))
c_config_file="config.php"
c_config_sample_file="config.sample.php"

c_conf_db_name='database_name'
c_conf_db_user='database_username'
c_conf_db_password='database_password'
c_conf_db_host='database_socket'
c_conf_password_salt='salt'
c_conf_secret='secret'
c_conf_game_master_secret='gameMasterSecret'
c_conf_json_secret='jsonSecret'
c_conf_email_address='yourdiplomacyserver.com'
c_conf_variants='variants'

c_inst_directory='install'
c_inst_db_file="$c_inst_directory/install.sql"

c_vari_todo_dir='variants_todo'
c_vari_done_dir='variants_done'
c_vari_main_file='variant.php'
c_vari_id='id'
c_vari_name='name'
c_vari_cache_dir='cache'

c_game_variants='variants'

# -----------------------------------------------
# create_config_file
# Erstellt die Konfigurationsdatei, wenn noch 
# nicht vorhanden...
# -----------------------------------------------
function create_config_file
{
  local config_file="$1/$2"
  local config_sample_file="$1/$3"

  if [ ! -f $config_file ]; then
    # Zunächst erstellen wir die Basis
    echo "... creating config file $config_file"
    cp $config_sample_file $config_file
    if [ $? -ne 0 ]; then
      echo "EEE Missing sample config file $config_sample_file"
      exit 5
    else
      echo "... done"
    fi

    # Nun denken wir uns einen Namen für den DB
    # Benutzer aus, der völlig zufällig gewählt
    # und geschriebe wird...
    echo "... generating db_username"
    local db_username=$(< /dev/urandom tr -dc _A-z-a-z-0-9 | head -c12)
    set_config_value $config_file $c_conf_db_user $db_username
    echo "... done"

    # Wir erstellen ein ebenso zufälliges Passwort
    echo "... generating db_password"
    local db_password=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
    set_config_value $config_file $c_conf_db_password $db_password
    echo "... done"

    # Den Datenbanknamen lassen wir uns vom Benutzer vorgeben...
    echo "... preparing Database Name"
    read -p "??? webDiplomacy DB Name [webDiplomacy]: " db_name
    if [ -z "$db_name" ]; then db_name='webDiplomacy'; fi
    set_config_value $config_file $c_conf_db_name $db_name
    echo "... done"

    # Den Datenbankhost ermitteln
    echo "... preparing Dabase Host"
    read -p "??? webDiplomacy DB Host [localhost]: " db_host
    if [ -z "$db_host" ]; then db_host='localhost'; fi
    set_config_value $config_file $c_conf_db_host $db_host
    echo '... done'

    # Erstellen des salt-Strings
    echo "... generating password salt"
    local password_salt=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
    set_config_value $config_file $c_conf_password_salt $password_salt
    echo "... done"

    # Erstellen des Schlüssels für die Generierung der SessionIds
    echo "... generating secret for session keys"
    local secret=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
    set_config_value $config_file $c_conf_secret $secret
    echo "... done"

    # Erstellen des GameMaster Passwords
    echo "... generating game master secret"
    local game_master_secret=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c16)
    set_config_value $config_file $c_conf_game_master_secret $game_master_secret
    echo "... done"

    # JSON Secret für die Cron-Prozesse
    echo "... generating json secret"
    local json_secret=$(< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c32)
    set_config_value $config_file $c_conf_json_secret $json_secret
    echo "... done"

    # Als letztes ändern wir noch alle tld's von den EMail-Adressen auf den
    # aktuellen Server
    echo "... adjusting email"
    local hostname=$(hostname -f)
    sed -i -e "s/@$c_conf_email_address/@$hostname/g" $config_file
    echo "... done"

  else
    echo "... configuration ready"
  fi
}


# -----------------------------------------------
# set_config_value
# Setzt einen Wert in der Konfigurationsdatei
# -----------------------------------------------
function set_config_value
{
  local config_file="$1"
  local config_key="$2"
  local config_value="$3"

  sed -i -e "s/$config_key\s*=\s*'.*'/$config_key='$config_value'/" $config_file
}
  
# -----------------------------------------------
# get_config_value
# Liefert einen Wert aus der Konfigurationsdatei
# zurück.
# -----------------------------------------------
function get_config_value
{
  local config_file="$1"
  local config_key="$2"

  local config_value=$(sed -ne "s/.*$config_key\s*=\s*'\(.*\)'.*/\1/p" $config_file)
  echo "$config_value"
}

# -----------------------------------------------
# create_database
# Prüfen, ob wir die Datenbank mit unserem Benutzer
# öffnen können. Sollte dies zu einem Fehler führen,
# dann bauen wir genau diese zunächst auf.
# -----------------------------------------------
function create_database 
{
  local config_file="$1/$2"
  
  # User, Datenbank und Passwort ermitteln
  local db_user=$(get_config_value $config_file $c_conf_db_user)
  local db_name=$(get_config_value $config_file $c_conf_db_name)
  local db_pwd=$(get_config_value $config_file $c_conf_db_password)
  local db_host=$(get_config_value $config_file $c_conf_db_host)

  # Prüfen, ob die Datenbank vorhanden und korrekt eingestellt ist
  echo '... check database connection'
   
  mysql                         \
    --user="'$db_user'"         \
    --host="$db_host"           \
    --password="$db_pwd"        \
    --database="$db_name"       \
    --unbuffered                \
    --execute="SELECT 1 + 1"    \
    &> /dev/null

  if [ $? -eq 0 ]; then
    echo '... database user available'
    return 0
  fi

  echo 'WWW Database User not available'
  echo "... Preparing Database"
  read -p "??? MySQL Admin Username [root]: " db_admin_user
  if [ -z "$db_admin_user" ]; then db_admin_user='root'; fi
  stty -echo
  read -p "??? MySQL Admin Password: " db_admin_pwd; echo 
  stty echo 
  echo 

  # Nun erstellen wir zunächst die eigentliche Datenbank für
  # das webDiplomacy
  echo '... creating database'
  mysql                         \
    --user="$db_admin_user"     \
    --password="$db_admin_pwd"  \
    --batch                     \
    --unbuffered                \
    <<< "CREATE DATABASE IF NOT EXISTS $db_name;" &> /dev/null
  if [ $? -ne 0 ]; then echo 'EEE failure'; exit 5; fi
  echo '... done'

  # Wir erstellen nun den Benutzer mit dem dazugehörenden Passwort
  mysql                         \
    --user="$db_admin_user"     \
    --password="$db_admin_pwd"  \
    --unbuffered                \
    <<< "CREATE USER '$db_user'@'$db_host' IDENTIFIED BY '$db_pwd';" &> /dev/null
  if [ $? -ne 0 ]; then echo 'EEE failure'; exit 5; fi
  echo '... done'

  # Nun werden entsprechende Rechte für den Benutzer erstellt
  mysql                         \
    --user="$db_admin_user"     \
    --password="$db_admin_pwd"  \
    --unbuffered                \
    <<< "GRANT ALL ON $db_name.* TO '$db_user'@'$db_host'"  &> /dev/null
  if [ $? -ne 0 ]; then echo 'EEE failure'; exit 5; fi
  echo '... done'
}

# -----------------------------------------------
# update_database
# Prüfen, ob die Datenbank aktualisiert werden
# darf bzw. muss.
# -----------------------------------------------
function update_database 
{
  local install_file="$1/$c_inst_db_file"
  local install_dir="$1/$c_inst_directory"
  local config_file="$1/$2"
  
  # User, Datenbank und Passwort ermitteln
  local db_user=$(get_config_value $config_file $c_conf_db_user)
  local db_name=$(get_config_value $config_file $c_conf_db_name)
  local db_pwd=$(get_config_value $config_file $c_conf_db_password)
  local db_host=$(get_config_value $config_file $c_conf_db_host)

  # Prüfen, ob die Datenbank vorhanden und korrekt eingestellt ist
  echo '... check database connection'
   
  mysql                         \
    --user="'$db_user'"         \
    --host="$db_host"           \
    --password="$db_pwd"        \
    --database="$db_name"       \
    --unbuffered                \
    --execute="SELECT 1 + 1" &> /dev/null

  if [ $? -ne 0 ]; then
    echo 'EEE database not available'
    return 5
  else
    echo '... database is available'
  fi

  echo '... get current version'
  local db_version=$(mysql      \
    --user="$db_user"           \
    --host="$db_host"           \
    --password="$db_pwd"        \
    --database="$db_name"       \
    --unbuffered                \
    --silent                    \
    --skip-column-names         \
    --execute="SELECT value FROM wD_Misc WHERE name='Version'" \
    2> /dev/null \
  )

  if [ -n "$db_version" ]; then
    echo "... current version $db_version"
  else
    echo 'WWW schemata is empty'
    echo '... building initial schemata'
    
    if [ ! -f "$install_file" ]; then
      echo "EEE DB installation file not available "
      echo "EEE missing file $install_file"
      return 5
    fi

    mysql                      \
      --user="'$db_user'"      \
      --host="$db_host"        \
      --password="$db_pwd"     \
      --database="$db_name"    \
      --unbuffered             \
      < $install_file          \
      &> /dev/null

    if [ $? -ne 0 ]; then
      echo "EEE DB installation failure."
      return 5
    fi

    # Nun versuchen wir noch einmal die Version der Datenbank
    # auszulesen und hoffen, dass wir dieses mal die richtige
    # Version auslesen können
    echo '... get current version'
    db_version=$(mysql            \
      --user="'$db_user'"         \
      --host="$db_host"           \
      --password="$db_pwd"        \
      --database="$db_name"       \
      --raw                       \
      --batch                     \
      --skip-column-names         \
      --unbuffered                \
      --silent                    \
      --execute="SELECT value FROM wD_Misc WHERE name='Version'" \
      2> /dev/null \
    )
    
    if [ $? -ne 0 ]; then 
      echo 'EEE version not available'
      return 5
    else
      echo "... current DB Version is $db_version"
    fi
  fi  
  
  # Prüfen, welche Versionen aktuell vorhanden sind und welche
  # davon für uns relevant oder praktikabel sind
  echo '... searching for updates'
 
  local update_folder=''
  local update_versions=''
  local update_folder_pattern='[[:digit:].-]'

  for update_folder in `ls -1d $install_dir/*/ | sort`; do
    # Den Verzeichnisnamen auf die Basis zurücksetzen...
    update_folder=$(basename $update_folder)

    # Sicherstellen, dass die Benennung der Verzeichnisse
    # passt
    [[ ! $update_folder =~ $update_folder_pattern ]] && continue

    # Prüfen, ob uns die Version für das Objekt auch zusagt
    # Hierfür packen wir das Objekt in eine Array und setzen
    # damit Quell- und Zielversion fest.
    update_versions=($(echo $update_folder | tr '-' ' ' | tr -d '.'))

    # Prüfen, ob die Ausgangsversion passt:
    if [ ${update_versions[0]} -ne $db_version ]; then
      # Wir müssen diesen Eintrag überspringen, da es sich nicht um die richtige
      # Ausgangsversion handelt
      echo "WWW source version ${update_versions[0]} doesn't fit to current version $db_version"
      echo "WWW skipping update $(basename $update_folder)"
      continue
    fi

    echo "... updating from ${update_versions[0]} to ${update_versions[1]}"

    # Prüfen, ob es eine Unterdatei gibt, die uns
    # interessieren könnte. Gibt es diese nicht, müssen wir trotzdem
    # die Versionsnummer erhöhen...
    if [ ! -f "${update_folder}update.sql" ]; then
      echo "... nothing todo"
      mysql                            \
        --user="'$db_user'"            \
        --host="$db_host"               \
        --password="$db_pwd"           \
        --database="$db_name"          \
        --unbuffered                   \
        --execute="UPDATE wD_Misc SET value=${update_versions[1]} WHERE name='Version'" \
        &> /dev/null

      if [ $? -eq 0 ]; then
        # Meldung ausgeben und die Versionsnummer umsetzen
        db_version=${update_versions[1]}
        echo "... done - current version set to $db_version"

      else
        # Meldung ausgeben, dass das Update nicht erfolgreich
        # war und wir direkt beenden...
        echo "EEE update not successfull - stopping"
        exit 5    
      fi
    else
      # Nun installieren wir das Update 
      echo "... updating schemata"
      mysql                            \
        --user="'$db_user'"            \
        --host="$db_host"               \
        --password="$db_pwd"           \
        --database="$db_name"          \
        --unbuffered                   \
        < "${update_folder}update.sql" \
        &> /dev/null

      if [ $? -eq 0 ]; then
        # Meldung ausgeben und die Versionsnummer umsetzen
        db_version=${update_versions[1]}
        echo "... done - current version set to $db_version"

      else
        # Meldung ausgeben, dass das Update nicht erfolgreich
        # war und wir direkt beenden...
        echo "EEE update not successfull - stopping"
        exit 5    
      fi
    fi
  done

}

# -----------------------------------------------
# set_rights
# -----------------------------------------------
function set_rights
{
  # Basisverzeichnis ermitteln
  local base_dir="$1"
  local inst_dir="$1/$c_inst_directory"

  # Ermitteln von Benutzer und Gruppe des WebServers
  local user=($(egrep -i '^user' /etc/httpd/conf/httpd.conf))
  local group=($(egrep -i '^group' /etc/httpd/conf/httpd.conf))
  local admin_user=($(users))
  local admin_group=($(groups))

  echo "... Setting rights to user: ${user[1]} group: ${group[1]}"

  # Nun setzen wir die Rechte auf die übergeordnete
  # Tabelle
  chown -R ${user[1]}:${group[1]} "$base_dir"

  # Verzeichnisse erhalten den Zugriffsmodus
  chmod -R 0750 "$base_dir"
  echo "... done"
 
  echo "... hiding install directory"
  # Eine Besonderheit stellt aber weiterhin das
  # Verzeichnis 'Installation' dar, welches wir
  # jetzt direkt wieder zurückstellen
  chown -R ${admin_user[0]}:${admin_group[0]} "$inst_dir"
  chmod -R 0700 "$inst_dir"

  echo "... done"
}

# -----------------------------------------------
# check_gameloop
# -----------------------------------------------
function check_gameloop
{
   local config_file="$1/$2"

   # Prüfen, ob der Eintrag bereits in der crontab
   # steht - wir erwarten dabei ausschließlich
   # informationen in der Benutzercrontab oder
   # der globalen cronttab (die aber vielleicht
   # nicht jedem zur Verfügung steht).
   echo '... look for existing gameloop entry'
   local crontab_entry=$(grep 'gamemaster.php' /etc/crontab)
   if [ -n "$crontab_entry" ]; then
     echo '... entry already in crontab.'
     return 0
   fi

   # Zunächst erstellen wir ein Backup der crontab
   echo '... create crontab backup'
   local datetime=$(date +%Y%m%d%H%M%S)
   cp /etc/crontab ~/${datetime}crontab
   echo "... backup to ~/${datetime}crontab done" 

   local hostname=$(hostname -f)
   local gamemaster_pwd=$(get_config_value $config_file  $c_conf_game_master_secret) 

   echo -e "*/5\t*\t*\t*\t*\t/usr/bin/wget -O - 'http://$hostname/gamemaster.php?gameMasterSecret=$gamemaster_pwd' >/dev/null 2>&1" >> /etc/crontab
   echo '... done'
}

# -----------------------------------------------
# enable_variants
# Prüft, ob in dem Verzeichnis variants_todo
# Varianten zum Einspielen vorhanden sind, die 
# dann direkt implementiert werden. Danach werden
# diese in den variants_done Ordner eingefügt.
# -----------------------------------------------
function enable_variants
{
  local config_file="$1/$2"
  local config_file_backup="${config_file}.bak"
  local variants_todo="$1/$c_inst_directory/$c_vari_todo_dir"
  local variants_done="$1/$c_inst_directory/$c_vari_done_dir"
  local variants_map
  local variants_installed=0
  declare -A variants_map
  local variants_dest="$1/$c_game_variants"

  # Zunächst werden die aktuell eingestellten Varianten
  # eingelesen...
  echo '... reading current variants'

  # wir müssen hier perl nutzen, da sed leider keine non-greedy
  # quantifier kennt
  local variants=$(grep "$c_conf_variants\s*=\s*" $config_file | \
                   perl -pe 's/.*\((.*?)\).*/\1/' | \
                   tr -d ' ' | tr ',' '\n')

  # Nun laufen wir über alle gefundenen Varianten
  # und versuchen diese dann stückweise zu ermitteln
  local variant=''
  local variant_name=''
  local variant_id=0
  for variant in $variants; do
    # Trennen der Varianen in Namen und Bezeichner
    variant=($(echo $variant | tr '=>' '\n'))
    variant_name=$(echo ${variant[1]} | tr -d "'")
    variant_id=${variant[0]}
    variant_map+=([$variant_id]="$variant_name")
    echo "... > ($variant_id) - $variant_name"
  done


  # Prüfen, ob die Dateien überhaupt vorhanden sind
  if [ ! -d "$variants_todo" ]; then
    echo "WWW Directory for additional variants"
    echo "WWW ($variants_todo)"
    echo "WWW is not available. Create directory"
    echo "WWW and copy variants archives to add"
    echo "WWW there."
    return 5
  fi

  # Zunächst ermitteln wir alle gepackten Varianten
  # und entpacken diese. Dann werden sie einzeln
  # untersucht und aktiviert...
  local variant_archive=''
  local variant_arc_base=''
  local variant_destination=''

  for variant_archive in `ls $variants_todo`; do
    # Es sollte sich um eine ZIP-Datei handeln...
    variant_arc_base=$(basename $variant_archive)
    if [[ $variant_arc_base =~ .*\.zip$ ]]; then
      echo "... found variant $variant_arc_base"
    else
      # skip
      continue
    fi

    variant_archive="$variants_todo/$variant_arc_base"

    # Zielverzeichnis ermitteln
    variant_destination=$(unzip -l $variant_archive | head -n4 | tail -n1 | awk '{ print $4 }' | xargs basename)
    variant_destination="$variants_dest/$variant_destination"
    variant_main_file="$variant_destination/$c_vari_main_file"

    # Entpacken der Datei ins Zielverzeichnis
    unzip $variant_archive -d $variants_dest 2>&1>/dev/null

    # Wir suchen nach der MapId und dem Namen der Map
    local vari_id=$(sed -ne "s/.*$c_vari_id\s*=\s*\([[:digit:]]*\).*/\1/p" $variant_main_file) 
    local vari_name=$(sed -ne "s/.*$c_vari_name\s*=\s*'\(.*\)'.*/\1/p" $variant_main_file)
    
    echo "... variant ($vari_id) $vari_name" 

    # Prüfen, ob die Id der variant bereits existiert
    if [ -z "${variant_map[$vari_id]}" ]; then
      echo "... variant id $vari_id is unique"
    else
      # In diesem Fall suchen wir eine passende Id
      echo "... variant id $vari_id is not unqiue"

      # So lange laufen lassen, bis wir wirkich eine neuen 
      # Eintrag gefunden haben...Dabei starten wir erst bei
      # der Variante 150
      vari_id=150
      while [ ${variant_map[$vari_id]+_} ]; do
        let vari_id=vari_id+1
        # hmmm ... das sollte nicht passieren
        if [ $vari_id -gt 999 ]; then 
          echo "EEE no free variant id found."
          exit 5
        fi
      done

      # In diesem Fall haben wir eine passende Id gefunden
      # und schreiben diese in die VariantMap hinein
      echo "... free variant id $vari_id for $vari_name found"
    fi

    # Merken der Variante für die Konfigurationsdatei
    variant_map+=([$vari_id]="$vari_name")

    # Wir haben zumindest eine Variante gefunden und
    # installiert
    variants_installed=1

    # Als letztes kopieren wir das ursprüngliche
    # Archiv in den 'done' Ordner
    mv $variant_archive "$variants_done"
  done

  # Updating configuration file with the new variants
  if [ $variants_installed -eq 1 ]; then
    echo "... taking backup from configuration file to $config_file_backup"
    cp --force "$config_file" "$config_file_backup"
    if [ $? -ne 0 ]; then
      echo "EEE config file backup not successfully."
      return 5
    fi

    # Securing backup
    chown $USER:$USER "$config_file_backup"
    chmod 0400 "$config_file_backup"
    echo "... done"

    echo "... Updating configuration file $config_file"
    variants=''
    local concat=''

    for vari_map_key in "${!variant_map[@]}"; do
      echo " ... > enabling variant ${variant_map[$vari_map_key]} (id $vari_map_key)"
      variants="$variants$concat$vari_map_key=>'${variant_map[$vari_map_key]}'"
      concat=','
    done

    # Updating the configuration file line
    sed -i -e "s/\(.*$c_conf_variants\s*=\s*.*(\)\(.*\)\()\s*;\)/\1$variants\3/" $config_file
    echo "... done"

  else
    echo "... no new variants found in folder $variants_todo"
  fi

}

# -----------------------------------------------
# check_variants_cache_dir
# -----------------------------------------------
function check_variants_cache_dir
{
  local config_file="$1/$2"
  local variants_map
  local variants_installed=0
  local variants_dest="$1/$c_game_variants"

  # Zunächst werden die aktuell eingestellten Varianten
  # eingelesen...
  echo '... reading current variants'

  # wir müssen hier perl nutzen, da sed leider keine non-greedy
  # quantifier kennt
  local variants=$(grep "$c_conf_variants\s*=\s*" $config_file | \
                   perl -pe 's/.*\((.*?)\).*/\1/' | \
                   tr -d ' ' | tr ',' '\n')

  # Nun laufen wir über alle gefundenen Varianten
  # und versuchen diese dann stückweise zu ermitteln
  local variant=''
  local variant_name=''
  local variant_id=0
  for variant in $variants; do
    # Trennen der Varianen in Namen und Bezeichner
    variant=($(echo $variant | tr '=>' '\n'))
    variant_name=$(echo ${variant[1]} | tr -d "'")
    variant_id=${variant[0]}
    echo "... > check variant $variant_name for cache directory"
    echo "... > try $variants_dest/$variant_name/$c_vari_cache_dir"
    if [ -d "$variants_dest/$variant_name/$c_vari_cache_dir" ]; then
      echo "SSS - cache dir in $variant_name available"
    else
      echo "... cache dir not available. Creating directory"
      mkdir "$variants_dest/$variant_name/$c_vari_cache_dir"
      echo "... <  done"
    fi 
  done

}

# -----------------------------------------------
# MAIN
# -----------------------------------------------

echo 'webDiplomacy Installer version 1.00'
echo '-----------------------------------'

# Zunächst prüfen wir, ob die Konfigurationsdatei
# bereits vorhanden ist oder wir diese noch erstellen
# sollen
echo '> check config file'
create_config_file        \
   $c_base                \
   $c_config_file         \
   $c_config_sample_file
echo '< done'

# Prüfen, ob der DB Benutzer, das Passwort und
# die Datenbank existieren...
echo '> check database user'
create_database           \
   $c_base                \
   $c_config_file
echo '< done'

# Eventuelles Update der Datenbanken prüfen
echo '> check schema version'
update_database           \
   $c_base                \
   $c_config_file
echo '< done'

# Prüfen der crontab-Einträge
echo '> check gameloop'
check_gameloop     \
  $c_base          \
  $c_config_file
echo '< done'

# Aktivieren von Varianten
echo '> adding new variants'
enable_variants    \
  $c_base          \
  $c_config_file   
echo '< done'

# checking for missing cache directories
echo '> preparing cache directories'
check_variants_cache_dir \
   $c_base                  \
   $c_config_file
echo '< done'

# Setzen der Rechte für die Verzeichnisse
echo '> set user rights'
set_rights \
  $c_base
echo '< done'
