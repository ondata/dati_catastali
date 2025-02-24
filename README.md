# Interrogare per attributo i dati catastali vettoriali dell'agenzia delle entrate

A inizio 2025 l'**agenzia delle entrate** [ha reso disponibili](https://geodati.gov.it/geoportale/visualizzazione-metadati/scheda-metadati/?uuid=age:S_0000_ITALIA) i dati catastali su fogli e particelle in formato vettoriale. Sono consultabili come servizio WFS e scaricabili in formato GML.

👉 È una buona notizia, ma c'è un grosso limite: **non è possibile interrogare i dati per attributo**, ma solo per geometria.<br>
E anche le ricerche geometriche/geografiche sono limitate.

Abbiamo quindi contattato l'Agenzia delle Entrate e purtroppo ci hanno comunicato che:

> sono abilitate solo le richieste in GET per GetCapabilities, DescribeFeatureType, GetFeature con il *boundig box* senza ulteriori filtri.

Ci sembrava utile trovare un'alternativa - anche soltanto parziale - e abbiamo realizzato un motore di *query*, che dato un **codice catastale comunale**, un **numero foglio** e un **numero particella**, **restituisce le coordinate di un punto della particella**.

Questa **coppia di coordinate** è quello che basta ad **avere restituito** dal WFS dell'agenzia delle entrate il **poligono della particella**, perché è interrogabile per geometria.<br>
Questa **coppia di coordinate**, come **risposta a una *query* per attributo** è il piccolo **servizio** che abbiamo reso **disponibile**.

## Come farlo

Il servizio è reso disponibile interrogando dei file parquet disponibili in HTTP. Infatti - come ha scritto Andrea Borruso - se si ha a disposizione un URL di un file `parquet` è un po' [come avere delle API](https://aborruso.github.io/posts/duckdb-intro-csv/#%C3%A8-come-avere-delle-api).

Con un *client* come [duckdb](https://duckdb.org/) (via `cli` o via linguaggio di *scripting*) è possibile infatti lanciare delle *query* `SQL` in modo diretto a un URL di un file `parquet`.

La prima *query* da fare è quella che, dato un **codice catastale comunale**, restituisce il nome del file parquet da interrogare per le particelle della regione in cui ricade il comune.

Ad esempio per il comune con codice "M011" (Villarosa) si può lanciare la seguente *query*:

```bash
duckdb -c "SELECT *
FROM 'https://raw.githubusercontent.com/ondata/dati_catastali/main/S_0000_ITALIA/anagrafica/index.parquet'
WHERE comune LIKE 'M011';"
```

In output si avrà (tra le altre cose) il nome del file da interrogare, che in questo caso è `19_Sicilia.parquet`:

```
          comune = M011
            file = 19_Sicilia.parquet
        CODISTAT = 086020
DENOMINAZIONE_IT = VILLAROSA
```

Non resta che interrogare per comune, foglio e particella il file `19_Sicilia.parquet`.<br>
Per avere ad esempio la coppia di coordinate della particella `2` del foglio `0002` del comune con codice catastale `M011`, è possibile lanciare:

```bash
duckdb -c "
    SELECT *
    FROM 'https://raw.githubusercontent.com/ondata/dati_catastali/main/S_0000_ITALIA/anagrafica/19_Sicilia.parquet'
    WHERE comune LIKE 'M011'
      AND foglio LIKE '0002'
      AND particella LIKE '2';
"
```

In output restituisce (si può provare [qui](https://sql-workbench.com/#queries=v0,SELECT-*-FROM-'https%3A%2F%2Fraw.githubusercontent.com%2Fondata%2Fdati_catastali%2Fmain%2FS_0000_ITALIA%2Fanagrafica%2F19_Sicilia.parquet'---where-comune-like-'M011'-and---foglio-like-'0002'-and---particella-like-'2'~)):

```
INSPIREID_LOCALID = IT.AGE.PLA.M011_000200.2
           comune = M011
           foglio = 0002
       particella = 2
                x = 14181642
                y = 37639896
```

Le **coordinate** `x` e `y` sono archiviate come **numeri interi**, per ottimizzare le dimensioni dei file `parquet`. Ma in realtà sono longitudine e latitudine espresse in gradi decimali, con 6 cifre decimali, moltiplicate per `1.000.000`. Ad esempio:

- Coordinate memorizzate: `x=14181642`, `y=37639896`
- Coordinate reali: `lon=14.181642`, `lat=37.639896`

Se si riportano le coordinate in gradi decimali e si costruisce un piccolo *bounding box* attorno a esse, si può interrogare il WFS dell'agenzia delle entrate per avere il poligono della particella.<br>

Una *query* WFS di esempio ha questa struttura:

`https://wfs.cartografia.agenziaentrate.gov.it/inspire/wfs/owfs01.php?language=ita&SERVICE=WFS&VERSION=2.0.0&TYPENAMES=CP:CadastralParcel&SRSNAME=urn:ogc:def:crs:EPSG::6706&BBOX=37.9999995,12.9999995,38.0000005,13.0000005&REQUEST=GetFeature&COUNT=100`

Se si [lancia](https://wfs.cartografia.agenziaentrate.gov.it/inspire/wfs/owfs01.php?language=ita&SERVICE=WFS&VERSION=2.0.0&TYPENAMES=CP:CadastralParcel&SRSNAME=urn:ogc:def:crs:EPSG::6706&BBOX=37.9999995,12.9999995,38.0000005,13.0000005&REQUEST=GetFeature&COUNT=100) si hanno restituiti in XML (il formato di default) i dati delle particelle comprese nel *bounding box* definito dalle coordinate `37.9999995,12.9999995,38.0000005,13.0000005`.

```xml
<wfs:FeatureCollection
    xmlns:CP="http://mapserver.gis.umn.edu/mapserver"
    xmlns:gml="http://www.opengis.net/gml/3.2"
    xmlns:wfs="http://www.opengis.net/wfs/2.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="
        http://mapserver.gis.umn.edu/mapserver
        https://wfs.cartografia.agenziaentrate.gov.it/inspire/wfs/owfs01.php?SERVICE=WFS&VERSION=2.0.0&REQUEST=DescribeFeatureType&TYPENAME=CP:CadastralParcel&OUTPUTFORMAT=application%2Fgml%2Bxml%3B%20version%3D3.2
        http://www.opengis.net/wfs/2.0
        http://schemas.opengis.net/wfs/2.0/wfs.xsd
        http://www.opengis.net/gml/3.2
        http://schemas.opengis.net/gml/3.2.1/gml.xsd"
    timeStamp="2025-02-23T20:26:50"
    numberMatched="1"
    numberReturned="1">

    <wfs:boundedBy>
        <gml:Envelope srsName="urn:ogc:def:crs:EPSG::6706">
            <gml:lowerCorner>37.999249 12.999534</gml:lowerCorner>
            <gml:upperCorner>38.000361 13.000943</gml:upperCorner>
        </gml:Envelope>
    </wfs:boundedBy>

    <wfs:member>
        <CP:CadastralParcel gml:id="CadastralParcel.IT.AGE.PLA.A176_003100.329">
            <gml:boundedBy>
                <gml:Envelope srsName="urn:ogc:def:crs:EPSG::6706">
                    <gml:lowerCorner>37.999249 12.999534</gml:lowerCorner>
                    <gml:upperCorner>38.000361 13.000943</gml:upperCorner>
                </gml:Envelope>
            </gml:boundedBy>

            <CP:msGeometry>
                <gml:Polygon gml:id="CadastralParcel.IT.AGE.PLA.A176_003100.329.1" srsName="urn:ogc:def:crs:EPSG::6706">
                    <gml:exterior>
                        <gml:LinearRing>
                            <gml:posList srsDimension="2">
                                38.00030250 12.99962227 38.00022463 12.99953415 37.99924858 13.00089595 37.99928465 13.00094337 38.00036148 12.99969166 38.00030250 12.99962227
                            </gml:posList>
                        </gml:LinearRing>
                    </gml:exterior>
                </gml:Polygon>
            </CP:msGeometry>

            <CP:INSPIREID_LOCALID>IT.AGE.PLA.A176_003100.329</CP:INSPIREID_LOCALID>
            <CP:INSPIREID_NAMESPACE>IT.AGE.PLA.</CP:INSPIREID_NAMESPACE>
            <CP:LABEL>329</CP:LABEL>
            <CP:NATIONALCADASTRALREFERENCE>A176_003100.329</CP:NATIONALCADASTRALREFERENCE>
            <CP:ADMINISTRATIVEUNIT>A176</CP:ADMINISTRATIVEUNIT>
        </CP:CadastralParcel>
    </wfs:member>

</wfs:FeatureCollection>

```

## Chi usa questi dati

La prima persona a usarli è stata **Salvatore Fiandaca**, che è anche stato colui che ci ha ispirato la creazione di questa banca dati.

Ha realizzato uno strumento per QGIS, di cui potete leggere qui:<br>
[Tool per QGIS](https://github.com/pigreco/download_ple_x_attributo_WFS_AdE)

[![](https://raw.githubusercontent.com/pigreco/download_ple_x_attributo_WFS_AdE/main/imgs/gui.png)](https://github.com/pigreco/download_ple_x_attributo_WFS_AdE)
