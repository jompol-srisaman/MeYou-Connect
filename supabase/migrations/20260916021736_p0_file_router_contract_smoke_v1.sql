do $$
declare
  v jsonb;
  probe record;
begin
  for probe in
    select * from (values
      ('image/jpeg','sample.jpg'),
      ('application/pdf','sample.pdf'),
      ('application/vnd.openxmlformats-officedocument.wordprocessingml.document','sample.docx'),
      ('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','sample.xlsx'),
      ('text/csv','sample.csv'),
      ('text/plain','sample.txt'),
      ('audio/mpeg','sample.mp3'),
      ('video/mp4','sample.mp4')
    ) as x(mime_type, filename)
  loop
    v := ops.file_intelligence_route_v1(probe.mime_type, probe.filename);
    if coalesce(v->>'route_key','') = '' then
      raise exception 'file router returned no route_key for % / %', probe.mime_type, probe.filename;
    end if;
  end loop;
end $$;
