# Análisis del transporte público de Wrocław: patrones de circulación y congestión por franja horaria

Análisis exploratorio y estadístico de ~25.7 millones de posiciones GPS del sistema de transporte público de Wrocław (Polonia), con el objetivo de caracterizar patrones de congestión y velocidad de tranvías y autobuses a lo largo del día.

## Pregunta de análisis

¿Cómo varía la proporción de tiempo parado y la velocidad de circulación de tranvías y autobuses a lo largo del día, y existe una diferencia sistemática entre ambos modos de transporte atribuible a que el tranvía circula por carril reservado?

## Datos

- **Fuente**: [Wrocław Public Transport](https://www.kaggle.com/datasets/pieca111/wroclaw-public-transport) (Kaggle)
- **Volumen**: 25,660,303 posiciones GPS individuales
- **Periodo**: 13–30 de abril de 2022 (27 días)
- **Cobertura**: 93 líneas (tranvía y autobús), ~69,500 identificadores de vehículo/sesión
- **Formato de trabajo**: SQLite (tabla `positions`), consultado desde R mediante `RSQLite`/`DBI` para evitar cargar el dataset completo en memoria

**Nota importante**: el dataset contiene únicamente posiciones GPS crudas (id de vehículo, línea, tipo, latitud/longitud, timestamp). No incluye horarios planificados (tipo GTFS), por lo que no es posible calcular retrasos respecto a un horario oficial. El análisis se centra en su lugar en velocidad de circulación y proporción de tiempo parado, ambas derivadas directamente de las trayectorias GPS.

## Metodología

### Limpieza y preparación

- Se descartaron identificadores de vehículo (`k`) con menos de 10 posiciones registradas, por corresponder probablemente a artefactos de reconexión del sistema de tracking, no a servicio real.
- La velocidad entre posiciones consecutivas de un mismo vehículo se calculó mediante distancia equirrectangular (aproximación válida a la escala de una ciudad) dividida por el tiempo transcurrido.
- Se excluyeron pares de posiciones con más de 180 segundos de diferencia temporal, al no poder garantizarse que representen un desplazamiento continuo.
- Se excluyeron velocidades calculadas superiores a 70 km/h, consideradas ruido de posicionamiento GPS más que circulación real.
- Se definió "parado" como velocidad inferior a 1 km/h (en vez de exactamente 0), para absorber el ruido de redondeo de coordenadas sin perder la distinción real entre movimiento y parada.

### Descubrimiento y tratamiento de la red de autobuses nocturnos

Durante la exploración se detectó que Wrocław opera una red de autobuses nocturnos con numeración propia (líneas 240–259, 206 y 602), que sustituye al servicio diurno cuando el tranvía reduce o cesa su operación (aproximadamente entre las 22h y la 1h). Esta red se trató como una categoría de servicio independiente (`bus_nocturno`), distinta del bus diurno, para evitar mezclar patrones de operación estructuralmente distintos en el mismo agregado horario.

Las combinaciones hora–categoría con menos de 5 líneas activas se marcaron como sin cobertura suficiente (`NA`) en lugar de eliminarse, de forma que los gráficos reflejen fielmente los huecos de servicio en vez de interpolar entre franjas sin datos.

### Test de hipótesis

Se planteó la hipótesis de que el tranvía, al circular por carril reservado, presenta menor proporción de tiempo parado que el autobús diurno, que comparte calzada con el tráfico general.

- Se comprobó normalidad de la variable `prop_parado` en ambos grupos (test de Shapiro-Wilk); ambos grupos se desviaron significativamente de la normalidad, por lo que se optó por un test no paramétrico (Wilcoxon/Mann-Whitney).
- Para evitar pseudo-replicación (tratar cada combinación línea-hora como una observación independiente cuando en realidad provienen de la misma línea), el test se realizó tanto a nivel línea-hora como a nivel agregado por línea.

## Hallazgos principales

1. **Patrón diario estable**: durante las horas de servicio normal (aprox. 2h–21h), tanto tranvía como autobús diurno muestran una proporción de tiempo parado y una velocidad media relativamente estables, sin picos de congestión pronunciados asociados a horas punta.

2. **Cierre nocturno del tranvía**: el número de líneas de tranvía activas cae de ~20 a 7 entre las 22h y la 1h, con las pocas unidades restantes mostrando proporciones de tiempo parado superiores al 90% — compatible con vehículos finalizando servicio hacia cochera, no circulación comercial activa.

3. **Red de autobuses nocturnos complementaria**: 18 líneas de autobús operan exclusivamente en horario nocturno (numeración 240–259, 206, 602), cubriendo la franja en la que el tranvía se retira. Esta red es prácticamente inexistente durante el día (1 línea residual con cobertura anecdótica).

4. **Diferencia tram vs. bus diurno — resultado matizado**:
   - A nivel línea-hora, el tranvía muestra menor proporción de tiempo parado que el bus diurno (Wilcoxon, p = 0.000164).
   - Al agregar correctamente por línea (n=75, evitando pseudo-replicación), la diferencia deja de ser significativa (p = 0.105), aunque se mantiene en la misma dirección (mediana tram = 0.575 vs. bus diurno = 0.607).
   - El tamaño del efecto es pequeño (r ≈ 0.14), sugiriendo que la ventaja del carril reservado, si existe, es real pero modesta, y el estudio no tiene potencia suficiente a nivel de línea para confirmarla con solidez.

## Limitaciones

- El dataset no incluye horarios planificados, por lo que no se puede medir retraso real respecto a un servicio esperado, solo velocidad y proporción de tiempo parado.
- El identificador de vehículo (`k`) probablemente corresponde a sesiones de conexión GPS, no a vehículos físicos persistentes, lo que impide un seguimiento longitudinal fiable de un mismo vehículo a lo largo de varios días.
- El test estadístico a nivel de línea tiene una muestra pequeña (n=75), limitando la potencia para detectar diferencias moderadas o pequeñas.
- El periodo cubierto es de 27 días de abril de 2022; los patrones podrían no ser representativos de otras estaciones del año (clima, vacaciones escolares, eventos).

## Reproducibilidad

**Requisitos**: R con los paquetes `RSQLite`, `DBI`, `dplyr`, `tidyr`, `ggplot2`.

**Datos**: descargar el dataset desde [Kaggle](https://www.kaggle.com/datasets/pieca111/wroclaw-public-transport) (archivo `.db`, tabla `positions`).

**Estructura del análisis**:
1. Conexión a la base de datos y exploración inicial de la tabla `positions`
2. Cálculo de velocidad y distancia entre posiciones consecutivas por vehículo (SQL, mediante funciones de ventana)
3. Agregación por línea y hora, con filtros de calidad (mínimo de observaciones, umbral de velocidad plausible)
4. Clasificación de líneas en categorías de servicio (tram / bus diurno / bus nocturno)
5. Visualización de patrones horarios por categoría
6. Test de hipótesis (Shapiro-Wilk + Wilcoxon) comparando tram vs. bus diurno

## Autor

Álvaro — [https://www.linkedin.com/in/álvaro-ruiz-gómez-a017763aa/]
