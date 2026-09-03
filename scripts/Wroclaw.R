#install.packages("RSQLite")
library(RSQLite)
library(DBI)
#Esto ess para disponer comodamente de la base de datos
con <- dbConnect(RSQLite::SQLite(), "positions.db")
#Aqui revisamos algunos datos simplones para poder tener una idea mejor de como son los datos
#Si no te acuerdas de como se hace estamos usando una libreria que lo hace igual que con SQL, asi que puedes volver a mirar
#la documentación del curso que has hecho (hablarse a uno mismo en primera persona es raro)
dbListTables(con)
dbGetQuery(con, "PRAGMA table_info(positions);")
dbGetQuery(con, "SELECT * FROM positions LIMIT 10;")
dbGetQuery(con, "SELECT COUNT(*) AS total_filas FROM positions;")
dbGetQuery(con,"SELECT MIN(timestamp) AS inicio, MAX(timestamp) AS fin FROM positions;")
dbGetQuery(con, "SELECT COUNT(DISTINCT name) AS lineas_distintas FROM positions;")
dbGetQuery(con, "SELECT COUNT(DISTINCT k) AS vehiculos_distintos FROM positions;")


actividad_por_linea <- dbGetQuery(con, "
  SELECT name, COUNT(*) AS n_pings
  FROM positions
  GROUP BY name
  ORDER BY n_pings DESC
  LIMIT 20;
")
actividad_por_linea

#Aqui hemos visto antes que hay muchos "vehiculos", por tanto no deberían de ser números de vehículos de verdad, si no de cada vez que 
#el coche sale, por ello nos interesa saber un poco mas sobre ellos

dbGetQuery(con, "SELECT COUNT(DISTINCT timestamp) AS timestamps_distintos FROM positions;")
dbGetQuery(con, "
  SELECT AVG(n) AS media_pings_por_k, MIN(n) AS min_pings, MAX(n) AS max_pings
  FROM (SELECT k, COUNT(*) AS n FROM positions GROUP BY k) sub;
")
dbGetQuery(con, "
  SELECT k, name, type, x, y, timestamp
  FROM positions
  WHERE k = 19679615
  ORDER BY timestamp
  LIMIT 20;
")
#Este último es un ejemplo de un tranvía al azar, con ello vemos que se mueve de forma normal, por ello podemos asegurar que
#cada k identifica una de los vehiculos. Por otro lado tenemos k con muy pocos pings, que seguramente sean fallos, además para la
#velocidad vemos que el salto temporal entre cada ping es arbitrario. Vamos a probar con una linea como ver la velocidad, para
#asegurar que es correcto.
prueba <- "
WITH filtrado AS (
  SELECT k, name, type, x, y, timestamp,
         COUNT(*) OVER (PARTITION BY k) AS n_pings
  FROM positions
  WHERE name = '31'
),
activos AS (
  SELECT * FROM filtrado WHERE n_pings >= 10
),
con_lag AS (
  SELECT
    k, name, type, x, y, timestamp,
    LAG(x) OVER (PARTITION BY k ORDER BY timestamp) AS prev_x,
    LAG(y) OVER (PARTITION BY k ORDER BY timestamp) AS prev_y,
    LAG(timestamp) OVER (PARTITION BY k ORDER BY timestamp) AS prev_ts
  FROM activos
)
SELECT *,
  (julianday(timestamp) - julianday(prev_ts)) * 86400 AS dt_segundos
FROM con_lag
WHERE prev_ts IS NOT NULL
LIMIT 20;
"
resultado <- dbGetQuery(con, prueba)
resultado

query_velocidad <- "
WITH filtrado AS (
  SELECT k, name, type, x, y, timestamp,
         COUNT(*) OVER (PARTITION BY k) AS n_pings
  FROM positions
  WHERE name = '31'
),
activos AS (
  SELECT * FROM filtrado WHERE n_pings >= 10
),
con_lag AS (
  SELECT
    k, name, type, x, y, timestamp,
    LAG(x) OVER (PARTITION BY k ORDER BY timestamp) AS prev_x,
    LAG(y) OVER (PARTITION BY k ORDER BY timestamp) AS prev_y,
    LAG(timestamp) OVER (PARTITION BY k ORDER BY timestamp) AS prev_ts
  FROM activos
),
con_dt AS (
  SELECT *,
    (julianday(timestamp) - julianday(prev_ts)) * 86400 AS dt_segundos
  FROM con_lag
  WHERE prev_ts IS NOT NULL
),
con_distancia AS (
  SELECT *,
    -- aproximación equirrectangular, radio tierra = 6371 km
    SQRT(
      POWER( RADIANS(y - prev_y) * COS(RADIANS((x + prev_x) / 2.0)) * 6371, 2) +
      POWER( RADIANS(x - prev_x) * 6371, 2)
    ) AS distancia_km
  FROM con_dt
  WHERE dt_segundos > 0
)
SELECT *,
  distancia_km / (dt_segundos / 3600.0) AS velocidad_kmh
FROM con_distancia
LIMIT 20;
"

test_velocidad <- dbGetQuery(con, query_velocidad)
test_velocidad

#Con esto tenemos una prueba con la linea 31, donde hemos eliminado las veces que ha salido con pocos pings, como última
#prueba vamos a ver en hora punta
query_velocidad_rush <- "
WITH filtrado AS (
  SELECT k, name, type, x, y, timestamp,
         COUNT(*) OVER (PARTITION BY k) AS n_pings
  FROM positions
  WHERE name = '31'
    AND timestamp BETWEEN '2022-04-14T08:00:00' AND '2022-04-14T09:00:00'
),
activos AS (
  SELECT * FROM filtrado WHERE n_pings >= 10
),
con_lag AS (
  SELECT
    k, name, type, x, y, timestamp,
    LAG(x) OVER (PARTITION BY k ORDER BY timestamp) AS prev_x,
    LAG(y) OVER (PARTITION BY k ORDER BY timestamp) AS prev_y,
    LAG(timestamp) OVER (PARTITION BY k ORDER BY timestamp) AS prev_ts
  FROM activos
),
con_dt AS (
  SELECT *,
    (julianday(timestamp) - julianday(prev_ts)) * 86400 AS dt_segundos
  FROM con_lag
  WHERE prev_ts IS NOT NULL
),
con_distancia AS (
  SELECT *,
    SQRT(
      POWER( RADIANS(y - prev_y) * COS(RADIANS((x + prev_x) / 2.0)) * 6371, 2) +
      POWER( RADIANS(x - prev_x) * 6371, 2)
    ) AS distancia_km
  FROM con_dt
  WHERE dt_segundos > 0
)
SELECT *,
  distancia_km / (dt_segundos / 3600.0) AS velocidad_kmh
FROM con_distancia
WHERE distancia_km > 0
LIMIT 20;
"

test_rush <- dbGetQuery(con, query_velocidad_rush)
test_rush

#Rapidamente vemos que hay un ruido en la linea 11, pues 140 km/h para un travia urbano es una locura. Por ello vamos a añadir
#un filtro a la velocidad para filtrar los ruidos. Además hay otro similar en la linea 14 pero en tiempo, en este caso apunta 
#a ser una pausa, pero tambien nos fastidia si queremos hacer un estudio de la velocidad media

query_velocidad_limpia <- "
WITH filtrado AS (
  SELECT k, name, type, x, y, timestamp,
         COUNT(*) OVER (PARTITION BY k) AS n_pings
  FROM positions
  WHERE name = '31'
    AND timestamp BETWEEN '2022-04-14T08:00:00' AND '2022-04-14T09:00:00'
),
activos AS (
  SELECT * FROM filtrado WHERE n_pings >= 10
),
con_lag AS (
  SELECT
    k, name, type, x, y, timestamp,
    LAG(x) OVER (PARTITION BY k ORDER BY timestamp) AS prev_x,
    LAG(y) OVER (PARTITION BY k ORDER BY timestamp) AS prev_y,
    LAG(timestamp) OVER (PARTITION BY k ORDER BY timestamp) AS prev_ts
  FROM activos
),
con_dt AS (
  SELECT *,
    (julianday(timestamp) - julianday(prev_ts)) * 86400 AS dt_segundos
  FROM con_lag
  WHERE prev_ts IS NOT NULL
    AND (julianday(timestamp) - julianday(prev_ts)) * 86400 BETWEEN 1 AND 180  -- descarta huecos > 3 min
),
con_distancia AS (
  SELECT *,
    SQRT(
      POWER( RADIANS(y - prev_y) * COS(RADIANS((x + prev_x) / 2.0)) * 6371, 2) +
      POWER( RADIANS(x - prev_x) * 6371, 2)
    ) AS distancia_km
  FROM con_dt
),
con_velocidad AS (
  SELECT *,
    distancia_km / (dt_segundos / 3600.0) AS velocidad_kmh
  FROM con_distancia
)
SELECT * FROM con_velocidad
WHERE velocidad_kmh <= 70  -- descarta velocidades no plausibles
ORDER BY timestamp
LIMIT 30;
"

test_limpio <- dbGetQuery(con, query_velocidad_limpia)
test_limpio
summary(test_limpio$velocidad_kmh)  

#HAcemos con filtros y hacemos un summary, para ver en limpio, vemos que encontramos una velocidad media lentilla,
# esto seguramente se deba a la medida del propio modelo, como no sabemos exactamente asumimos que se trata
# de mediciones muy seguidas y cuando el tranvia/bus se encuentra parado en una estacion/semaforo

#Ahora vamos a hacer completo

query_agregado_completo <- "
WITH filtrado AS (
  SELECT k, name, type, x, y, timestamp,
         COUNT(*) OVER (PARTITION BY k) AS n_pings
  FROM positions
),
activos AS (
  SELECT * FROM filtrado WHERE n_pings >= 10
),
con_lag AS (
  SELECT
    k, name, type, x, y, timestamp,
    LAG(x) OVER (PARTITION BY k ORDER BY timestamp) AS prev_x,
    LAG(y) OVER (PARTITION BY k ORDER BY timestamp) AS prev_y,
    LAG(timestamp) OVER (PARTITION BY k ORDER BY timestamp) AS prev_ts
  FROM activos
),
con_dt AS (
  SELECT *,
    (julianday(timestamp) - julianday(prev_ts)) * 86400 AS dt_segundos
  FROM con_lag
  WHERE prev_ts IS NOT NULL
    AND (julianday(timestamp) - julianday(prev_ts)) * 86400 BETWEEN 1 AND 180
),
con_distancia AS (
  SELECT *,
    SQRT(
      POWER( RADIANS(y - prev_y) * COS(RADIANS((x + prev_x) / 2.0)) * 6371, 2) +
      POWER( RADIANS(x - prev_x) * 6371, 2)
    ) AS distancia_km
  FROM con_dt
),
con_velocidad AS (
  SELECT *,
    distancia_km / (dt_segundos / 3600.0) AS velocidad_kmh,
    CAST(strftime('%H', timestamp) AS INTEGER) AS hora
  FROM con_distancia
  WHERE distancia_km / (dt_segundos / 3600.0) <= 70
)
SELECT
  name,
  type,
  hora,
  COUNT(*) AS n_observaciones,
  SUM(CASE WHEN velocidad_kmh = 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_parado,
  AVG(CASE WHEN velocidad_kmh > 0 THEN velocidad_kmh END) AS vel_media_en_movimiento,
  AVG(velocidad_kmh) AS vel_media_global
FROM con_velocidad
GROUP BY name, type, hora
ORDER BY name, hora;
"

# Esto tarda
agregado_completo <- dbGetQuery(con, query_agregado_completo)

# Vista rápida del resultado
head(agregado_completo, 20)
dim(agregado_completo)

#Aqui vemos otro fallo, sobre la mañana vemos que la vel media es demasiado baja, ademas de un bajo porcentaje de parados
#Aunque lo segundo es explicable (puede no haber tanta pausa para subir a viajeros), la primera es rara, esto se debera
#a que fallos en el GPS miden que el coche se está moviendo, aun estando parado, vamos a considerar un mayor margen de fallo

query_agregado_v2 <- "
WITH filtrado AS (
  SELECT k, name, type, x, y, timestamp,
         COUNT(*) OVER (PARTITION BY k) AS n_pings
  FROM positions
),
activos AS (
  SELECT * FROM filtrado WHERE n_pings >= 10
),
con_lag AS (
  SELECT
    k, name, type, x, y, timestamp,
    LAG(x) OVER (PARTITION BY k ORDER BY timestamp) AS prev_x,
    LAG(y) OVER (PARTITION BY k ORDER BY timestamp) AS prev_y,
    LAG(timestamp) OVER (PARTITION BY k ORDER BY timestamp) AS prev_ts
  FROM activos
),
con_dt AS (
  SELECT *,
    (julianday(timestamp) - julianday(prev_ts)) * 86400 AS dt_segundos
  FROM con_lag
  WHERE prev_ts IS NOT NULL
    AND (julianday(timestamp) - julianday(prev_ts)) * 86400 BETWEEN 1 AND 180
),
con_distancia AS (
  SELECT *,
    SQRT(
      POWER( RADIANS(y - prev_y) * COS(RADIANS((x + prev_x) / 2.0)) * 6371, 2) +
      POWER( RADIANS(x - prev_x) * 6371, 2)
    ) AS distancia_km
  FROM con_dt
),
con_velocidad AS (
  SELECT *,
    distancia_km / (dt_segundos / 3600.0) AS velocidad_kmh,
    CAST(strftime('%H', timestamp) AS INTEGER) AS hora
  FROM con_distancia
  WHERE distancia_km / (dt_segundos / 3600.0) <= 70
)
SELECT
  name,
  type,
  hora,
  COUNT(*) AS n_observaciones,
  SUM(CASE WHEN velocidad_kmh < 1 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS prop_parado,
  AVG(CASE WHEN velocidad_kmh >= 1 THEN velocidad_kmh END) AS vel_media_en_movimiento,
  AVG(velocidad_kmh) AS vel_media_global
FROM con_velocidad
GROUP BY name, type, hora
ORDER BY name, hora;
"

agregado_v2 <- dbGetQuery(con, query_agregado_v2)
head(agregado_v2, 25)

#Ahora obtenemos algo más realista, pues de madrugada no deberia de haber mucho movimiento

#Procedemos con los gráficos
#install.packages("dplyr")
#install.packages("ggplot2")
library(dplyr)
library(ggplot2)

agregado_v2$type <- as.factor(agregado_v2$type)
agregado_v2 %>% 
  group_by(type) %>% 
  summarise(n_lineas = n_distinct(name))
patron_horario <- agregado_v2 %>%
  group_by(hora, type) %>%
  summarise(
    prop_parado_media = mean(prop_parado, na.rm = TRUE),
    vel_movimiento_media = mean(vel_media_en_movimiento, na.rm = TRUE),
    .groups = "drop"
  )
ggplot(patron_horario, aes(x = hora, y = prop_parado_media, color = type)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Proporción de tiempo parado por hora del día",
       x = "Hora del día", y = "Proporción parado", color = "Tipo") +
  theme_minimal()
ggplot(patron_horario, aes(x = hora, y = vel_movimiento_media, color = type)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Velocidad media en movimiento por hora del día",
       x = "Hora del día", y = "km/h", color = "Tipo") +
  theme_minimal()

#Aqui hemos encontrado un posible problema, los autobuses en el cambio de día presentan una actividad extraña
#Por ello vamos a pararnos a ver que puede causar esto
resultado <- agregado_v2 %>%
  filter(type == "bus", hora %in% c(22, 23, 0, 1)) %>%
  arrange(hora, desc(n_observaciones)) %>%
  select(name, hora, n_observaciones, prop_parado, vel_media_en_movimiento)

head(resultado, 50)
agregado_v2 %>%
  filter(type == "bus") %>%
  group_by(hora) %>%
  summarise(
    n_lineas_activas = n_distinct(name),
    total_observaciones = sum(n_observaciones),
    .groups = "drop"
  ) %>%
  arrange(hora) %>%
  print(n = 24)

#Ahora podemos ver el problema, estamos dandole mucho peso lineas que no deberían de contar con tanto peso
#Vamos a hacer una media ponderada entonces
patron_horario_v2 <- agregado_v2 %>%
  filter(n_observaciones >= 100) %>%   # descarta combinaciones línea-hora poco fiables
  group_by(hora, type) %>%
  summarise(
    prop_parado_media = weighted.mean(prop_parado, w = n_observaciones, na.rm = TRUE),
    vel_movimiento_media = weighted.mean(vel_media_en_movimiento, w = n_observaciones, na.rm = TRUE),
    n_lineas_incluidas = n(),
    total_obs = sum(n_observaciones),
    .groups = "drop"
  )

# Repetimos los gráficos con esta versión corregida
ggplot(patron_horario_v2, aes(x = hora, y = prop_parado_media, color = type)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Proporción de tiempo parado por hora (ponderado, n≥100)",
       x = "Hora del día", y = "Proporción parado", color = "Tipo") +
  theme_minimal()

ggplot(patron_horario_v2, aes(x = hora, y = vel_movimiento_media, color = type)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Velocidad media en movimiento por hora (ponderado, n≥100)",
       x = "Hora del día", y = "km/h", color = "Tipo") +
  theme_minimal()

patron_horario_v2 %>%
  filter(type == "bus", hora %in% c(22, 23, 0, 1)) %>%
  as_tibble() %>%
  print(n = 20)
  
#más revisiones para ver cosas, ahora sin filtrar solo los buses

patron_horario_v2 %>%
  as_tibble() %>%
  filter(hora %in% c(22, 23, 0, 1)) %>%
  arrange(type, hora) %>%
  print(n = 20)
agregado_v2 %>%
  as_tibble() %>%
  filter(type == "tram", hora %in% c(22, 23, 0, 1), n_observaciones >= 100) %>%
  arrange(hora, desc(n_observaciones)) %>%
  select(name, hora, n_observaciones, prop_parado, vel_media_en_movimiento) %>%
  print(n = 30)

#Con esto vemos que lo que parecia un problema de data se trata de una maniobra de operación, los autobuses no parán
#y tenemos menos datos de autobuses parados. Con esto estamos cada vez más cerca de poder hacer cosas con la información.

#Vamos a hacer un gráfico ahora donde la idea es mostrar la proporción de tiempo parado por hora de cada autobus
patron_horario_v2 %>%
  filter(!(type == "tram" & hora %in% c(23, 0))) %>%
  ggplot(aes(x = hora, y = prop_parado_media, color = type)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Proporción de tiempo parado por hora (servicio activo)",
       x = "Hora del día", y = "Proporción parado", color = "Tipo") +
  theme_minimal()

#Con este vamos a ver el numero de lineas que funcionan
agregado_v2 %>%
  filter(n_observaciones >= 100) %>%
  group_by(hora, type) %>%
  summarise(n_lineas_activas = n_distinct(name), .groups = "drop") %>%
  ggplot(aes(x = hora, y = n_lineas_activas, color = type)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Líneas activas por hora (n≥100 obs.)",
       x = "Hora del día", y = "Nº de líneas", color = "Tipo") +
  theme_minimal()

#Aqui vemos algo más que me parece de interes, encontramos un pico de lineas activas en horas extrañas, así que estaría bien
#investigar esto. Para ello vamos a hacer dos listas de datos donde vamos a ver explicitamente el día frente a la madrugada

lineas_madrugada <- agregado_v2 %>%
  filter(type == "bus", hora %in% c(2, 3, 4), n_observaciones >= 100) %>%
  distinct(name) %>%
  pull(name)

lineas_dia <- agregado_v2 %>%
  filter(type == "bus", hora == 10, n_observaciones >= 100) %>%
  distinct(name) %>%
  pull(name)

length(lineas_madrugada)
length(lineas_dia)
length(intersect(lineas_madrugada, lineas_dia))
setdiff(lineas_madrugada, lineas_dia)  # líneas que SOLO existen de madrugada
setdiff(lineas_dia, lineas_madrugada) # líneas que SOLO existen de dia

#Encontramos que los autobuses nocturnos se complementan con los autobuses diurnos. Vamos a revisar tambien la lista
#de los autobuses tardios para comprobar si hay ciertos autobuses adicionales tambien o son los mismos

lineas_tarde <- agregado_v2 %>%
  filter(type == "bus", hora %in% c(20, 21), n_observaciones >= 100) %>%
  distinct(name) %>%
  pull(name)

length(lineas_tarde)
length(intersect(lineas_madrugada, lineas_tarde))
length(intersect(lineas_tarde, lineas_dia))
setdiff(lineas_madrugada, lineas_tarde)


setdiff(lineas_tarde, lineas_dia)
setdiff(setdiff(lineas_madrugada, lineas_dia),setdiff(lineas_tarde, lineas_dia))

#Podemos ver que hay un par de lineas que solo estan durante el dia y no por la noche, en especifico en los momentos que 
#tendria sentido tener más afluencia de pasajeros. Por ello podríamos esperar tres grupos de autobuses
#Diurnos
#Nocturnos
#De refuerzo
#Además si bien algunos de los nocturnos registran en horarios extraños para ser nocturnos esto puede tratarse a una 
#recolocación de la flota para poder salir en el inicio de su horario

#Para las de refuerzo vamos a dejarlas ahi, pues tampoco queremos dar muchs vueltas, asi que vamos a dividir
#las variables entre las nocturnas y las diurnas
lineas_nocturnas <- c(as.character(206:259), "602")
agregado_v2 <- agregado_v2 %>%
  mutate(
    categoria_servicio = case_when(
      type == "tram" ~ "tram",
      type == "bus" & name %in% lineas_nocturnas ~ "bus_nocturno",
      type == "bus" ~ "bus_diurno",
      TRUE ~ NA_character_
    )
  )
#verificación rapida
agregado_v2 %>%
  distinct(name, categoria_servicio) %>%
  count(categoria_servicio)
#ahora dividimos en 3 categorias
patron_horario_v4 <- agregado_v2 %>%
  filter(n_observaciones >= 100) %>%
  group_by(hora, categoria_servicio) %>%
  summarise(
    prop_parado_media = weighted.mean(prop_parado, w = n_observaciones, na.rm = TRUE),
    vel_movimiento_media = weighted.mean(vel_media_en_movimiento, w = n_observaciones, na.rm = TRUE),
    n_lineas_incluidas = n(),
    total_obs = sum(n_observaciones),
    .groups = "drop"
  )
ggplot(patron_horario_v4, aes(x = hora, y = prop_parado_media, color = categoria_servicio)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Proporción de tiempo parado por hora y tipo de servicio",
       x = "Hora del día", y = "Proporción parado", color = "Categoría") +
  theme_minimal()

ggplot(patron_horario_v4, aes(x = hora, y = vel_movimiento_media, color = categoria_servicio)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Velocidad media en movimiento por hora y tipo de servicio",
       x = "Hora del día", y = "km/h", color = "Categoría") +
  theme_minimal()

#Vemos aqui picos raros en el nocturno, vamos a ver a que se puede deber
agregado_v2 %>%
  filter(categoria_servicio == "bus_nocturno") %>%
  group_by(hora) %>%
  summarise(
    n_lineas_activas = n_distinct(name),
    total_obs = sum(n_observaciones),
    .groups = "drop"
  ) %>%
  arrange(hora) %>%
  print(n = 24)

#Vemos que son cosas puntuales, ya bien traslados, servicios puntuales o un fallo en la información. Es por ello que le vamos a poner
#un filtro adicional
patron_horario_v5 <- agregado_v2 %>%
  filter(n_observaciones >= 100) %>%
  group_by(hora, categoria_servicio) %>%
  summarise(
    n_lineas_activas = n_distinct(name),
    prop_parado_media = weighted.mean(prop_parado, w = n_observaciones, na.rm = TRUE),
    vel_movimiento_media = weighted.mean(vel_media_en_movimiento, w = n_observaciones, na.rm = TRUE),
    total_obs = sum(n_observaciones),
    .groups = "drop"
  ) %>%
  filter(n_lineas_activas >= 5)   # descarta horas con cobertura residual/anecdótica

ggplot(patron_horario_v5, aes(x = hora, y = prop_parado_media, color = categoria_servicio)) +
  geom_line(linewidth = 1) +
  geom_point() +
  labs(title = "Proporción de tiempo parado por hora y tipo de servicio",
       subtitle = "Excluidas horas con cobertura residual (<5 líneas activas)",
       x = "Hora del día", y = "Proporción parado", color = "Categoría") +
  theme_minimal()
#Aqui vemos que la grafica se queda un poco extraña
#install.packages("tidyr")
library(tidyr)
patron_horario_v5_completo <- agregado_v2 %>%
  filter(n_observaciones >= 100) %>%
  group_by(hora, categoria_servicio) %>%
  summarise(
    n_lineas_activas = n_distinct(name),
    prop_parado_media = weighted.mean(prop_parado, w = n_observaciones, na.rm = TRUE),
    vel_movimiento_media = weighted.mean(vel_media_en_movimiento, w = n_observaciones, na.rm = TRUE),
    total_obs = sum(n_observaciones),
    .groups = "drop"
  ) %>%
  mutate(
    prop_parado_media = if_else(n_lineas_activas >= 5, prop_parado_media, NA_real_),
    vel_movimiento_media = if_else(n_lineas_activas >= 5, vel_movimiento_media, NA_real_)
  ) %>%
  complete(hora = 0:23, categoria_servicio)  # rellena huecos de hora-categoría con NA

ggplot(patron_horario_v5_completo, aes(x = hora, y = prop_parado_media, color = categoria_servicio)) +
  geom_line(linewidth = 1, na.rm = FALSE) +
  geom_point() +
  labs(title = "Proporción de tiempo parado por hora y tipo de servicio",
       subtitle = "Huecos = sin cobertura suficiente en esa franja horaria",
       x = "Hora del día", y = "Proporción parado", color = "Categoría") +
  theme_minimal()
#Por ultimo vamos a hacer algo de test sobre los datos, como por ejemplo ver si la proporcion de parados entre diurnos y tram
#es significativa o es azar. Es decir, presentan una diferencia significante o no

datos_test <- agregado_v2 %>%
  filter(
    categoria_servicio %in% c("tram", "bus_diurno"),
    n_observaciones >= 100,
    hora %in% 6:20   # horas de servicio diurno normal, evita transiciones nocturnas
  )

# Recuerdas inferencia? pues eso
shapiro.test(datos_test$prop_parado[datos_test$categoria_servicio == "tram"])
shapiro.test(datos_test$prop_parado[datos_test$categoria_servicio == "bus_diurno"])

# Visual rápido de las distribuciones

ggplot(datos_test, aes(x = prop_parado, fill = categoria_servicio)) +
  geom_density(alpha = 0.5) +
  theme_minimal()
#Los test presentan bajo p-val asi que seguiremos con un test de wilcox

levels(as.factor(datos_test$categoria_servicio))

wilcox.test(prop_parado ~ categoria_servicio, data = datos_test, alternative = "two.sided")
wilcox.test(prop_parado ~ categoria_servicio, data = datos_test, alternative = "greater")

#Rechazamos h0
datos_por_linea <- datos_test %>%
  group_by(name, categoria_servicio) %>%
  summarise(prop_parado_linea = weighted.mean(prop_parado, w = n_observaciones), .groups = "drop")

wilcox.test(prop_parado_linea ~ categoria_servicio, data = datos_por_linea, alternative = "greater")
datos_por_linea %>% count(categoria_servicio)
#p-val de 0.1, por tanto tenemos algo mas interesante. Por que se da esto? Pues aquí hemos limpiado la repeticion de datos 
#"ligeros". Por vamos a ver un poco mas el tamaño del efecto
datos_por_linea %>%
  group_by(categoria_servicio) %>%
  summarise(
    mediana = median(prop_parado_linea),
    media = mean(prop_parado_linea),
    n = n()
  )
wilcox_result <- wilcox.test(prop_parado_linea ~ categoria_servicio, data = datos_por_linea, 
                             alternative = "greater", exact = FALSE)
z_approx <- qnorm(1 - wilcox_result$p.value)
r_efecto <- z_approx / sqrt(nrow(datos_por_linea))
r_efecto
