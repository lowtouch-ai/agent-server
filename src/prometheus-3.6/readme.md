# Prometheus

Once the prometheus is installed and running, you can verify it  by curling the /-/ready  endpoint:
```
curl http://localhost:9090/-/ready
```
You should see output like this:
```
Prometheus is Ready
```
you can verify the metrics  by curling the /metrics endpoint:

 ```
curl http://localhost:9090/metrics

   ```
You should see output like this:

```
# HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
# TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 4.6211e-05
go_gc_duration_seconds{quantile="0.25"} 9.1655e-05
go_gc_duration_seconds{quantile="0.5"} 0.000199154
go_gc_duration_seconds{quantile="0.75"} 0.000405769
go_gc_duration_seconds{quantile="1"} 0.052351147
go_gc_duration_seconds_sum 0.135360124
go_gc_duration_seconds_count 254
# HELP go_goroutines Number of goroutines that currently exist.
# TYPE go_goroutines gauge
go_goroutines 35
# HELP go_info Information about the Go environment.
# TYPE go_info gauge
go_info{version="go1.16.4"} 1
# HELP go_memstats_alloc_bytes Number of bytes allocated and still in use.
# TYPE go_memstats_alloc_bytes gauge
go_memstats_alloc_bytes 2.5357208e+07
# HELP go_memstats_alloc_bytes_total Total number of bytes allocated, even if freed.
# TYPE go_memstats_alloc_bytes_total counter
go_memstats_alloc_bytes_total 2.552613696e+09
# HELP go_memstats_buck_hash_sys_bytes Number of bytes used by the profiling bucket hash table.
# TYPE go_memstats_buck_hash_sys_bytes gauge
go_memstats_buck_hash_sys_bytes 1.578088e+06
# HELP go_memstats_frees_total Total number of frees.
# TYPE go_memstats_frees_total counter
go_memstats_frees_total 9.552972e+06
# HELP go_memstats_gc_cpu_fraction The fraction of this program's available CPU time used by the GC since the program started
```

Also You can check the prometheus.log in "/appz/log"

You should see the  line "Server is ready to receive web requests" in log :

```
level=info ts=2021-06-18T06:51:24.808Z caller=main.go:828 fs_type=794c7630
level=info ts=2021-06-18T06:51:24.808Z caller=main.go:831 msg="TSDB started"
level=info ts=2021-06-18T06:51:24.808Z caller=main.go:957 msg="Loading configuration file" filename=/opt/bitnami/prometheus/conf/prometheus.yml
level=info ts=2021-06-18T06:51:24.810Z caller=main.go:988 msg="Completed loading of configuration file" filename=/opt/bitnami/prometheus/conf/prometheus.yml totalDuration=1.434422ms remote_storage=2.414µs web_handler=500ns query_engine=1.423µs scrape=581.903µs scrape_sd=147.57µs notify=25.688µs notify_sd=39.462µs rules=1.421µs
level=info ts=2021-06-18T06:51:24.810Z caller=main.go:775 msg="Server is ready to receive web requests."

```
