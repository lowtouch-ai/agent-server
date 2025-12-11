path "auth/approle/login" {
 capabilities = [ "create", "read" ]
}


path "secret/app-0-4/*" {
 capabilities = [ "read", "list" ]
}
