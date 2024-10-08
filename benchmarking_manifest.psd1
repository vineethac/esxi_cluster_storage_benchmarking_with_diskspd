#Configuration data for benchmarking tests

@{
    vcenter             = "192.168.105.101"
    cluster_name        = "Cluster01"
    vm_template_name    = "testvm-win2016-template"
    VM_count_per_host   = "5"
    disk_size           = "6"
    disk_aus_in_bytes   = "65536"
    datastore_names     = @("vol01","vol02","vol03")

    gateway             = "192.168.150.100"
    pd_id               = "4db4512700000000"

}