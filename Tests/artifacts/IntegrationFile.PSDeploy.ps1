Deploy Files {
    By Filesystem {
        FromSource Modules\File1.ps1
        To TestDrive:\
        WithOptions @{
            Mirror = $False
        }
        Tagged Testing
    }
}
