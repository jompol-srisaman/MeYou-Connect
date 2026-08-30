create index if not exists alert_instances_alert_rule_idx on ops.alert_instances(alert_rule_key);
create index if not exists alert_delivery_queue_route_idx on ops.alert_delivery_queue(route_pk);