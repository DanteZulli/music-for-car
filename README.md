# music-for-car.sh

Bash script para procesar musica de cualquier formato a MP3 optimizado para pendrive de auto.

## Contexto

Creado para mi **Sony CDX-GT500US** con un pendrive de 64GB. La musica original estaba en FLAC (y otros formatos) con portadas, lyrics files, y nombres con caracteres especiales que el estereo no leia correctamente.

## Que hace

- **Convierte** todo audio (FLAC, OGG, OPUS, M4A, WAV, AAC, WMA) a **MP3 256kbps CBR**
- **Normaliza** volumen con `loudnorm` two-pass (I=-16 LUFS, TP=-1.5 dBTP, LRA=11 LU)
- **Highpass** a 100 Hz para eliminar rumble que los parlantes del auto no reproducen
- **Sanea** nombres de carpetas y archivos a ASCII puro (sin acentos, sin simbolos raros)
- **Limpia** metadatos ID3: solo deja title, artist, album, track, genre
- **Solo audio**: descarta imagenes de portada, archivos .lrc, y cualquier no-audio

## Requisitos

- `ffmpeg` (con libmp3lame)
- `ffprobe` (viene con ffmpeg)
- `iconv`
- `fatsort` (para ordenar fisicamente el pendrive despues de copiar)

## Uso

```bash
./music-for-car.sh <carpeta_fuente> <carpeta_destino>
```

### Un album individual

```bash
./music-for-car.sh ~/Music/"2 Minutos - Vida Monotona (2015)" ~/mp3_para_auto
```

Procesa un solo album y lo guarda como `Banda - Album` en el destino.

### Toda la musica

```bash
./music-for-car.sh ~/Music ~/mp3_para_auto
```

Procesa todos los albums en el directorio fuente y los guarda como `NN - Banda - Album` (numerados secuencialmente).

## Flujo completo para el pendrive

### 1. Procesar la musica

```bash
./music-for-car.sh ~/Music ~/mp3_para_auto
```

### 2. Formatear el pendrive en FAT32

```bash
# Verificar el dispositivo correcto con lsblk
lsblk

# Desmontar
sudo umount /dev/sdX1

# Formatear
sudo mkfs.vfat -F 32 -n "MUSICA_AUTO" /dev/sdX1
```

### 3. Copiar los archivos

```bash
# Montar
sudo mount /dev/sdX1 /run/media/dante/MUSICA_AUTO

# Copiar
cp -r ~/mp3_para_auto/* /run/media/dante/MUSICA_AUTO/
```

### 4. Ordenar con fatsort (CRUCIAL)

El Sony CDX-GT500US lee los archivos en el orden fisico en que aparecen en la tabla de directorios FAT, **no** en orden alfabetico. `fatsort` reordena fisicamente las entradas para que el estereo los lea correctamente.

```bash
# Desmontar primero (fatsort requiere el dispositivo desmontado)
sudo umount /run/media/dante/MUSICA_AUTO

# Ordenar
sudo fatsort /dev/sdX1

# Volver a montar
sudo mount /dev/sdX1 /run/media/dante/MUSICA_AUTO
```

### 5. Desmontar y usar

```bash
sudo umount /run/media/dante/MUSICA_AUTO
```

## Formato de carpeta esperado

El script espera que la carpeta fuente tenga albums con el formato:

```
Banda - Nombre del Disco (Anio)/
  01 - Cancion.flac
  02 - Cancion.flac
  cover.jpg
```

El `(Anio)` al final es opcional. Todo lo demas se parsea como `Banda` y `Disco`.

## Formato de salida

### Carpetas

- **Modo multi-album**: `01 - Banda - Nombre del Disco`
- **Modo album individual**: `Banda - Nombre del Disco`

### Archivos

- `01 - Nombre de la Cancion.mp3`
- `02 - Otra Cancion.mp3`

Todos los nombres son ASCII puro: sin acentos, sin `n`, sin comillas, sin parentesis.

### Audio

| Propiedad | Valor |
|---|---|
| Codec | MP3 (libmp3lame) |
| Bitrate | 256 kbps CBR |
| Sample rate | 44100 Hz |
| Canales | 2 (stereo) |
| Highpass | 100 Hz |
| Loudness | -16 LUFS (two-pass loudnorm) |
| True Peak | -1.5 dBTP |
| LRA | 11 LU |

### Metadatos ID3v2.3

Solo se incluyen: `title`, `artist`, `album`, `track`, `genre`. Se elimina todo lo demas (imagenes embedidas, comentarios, encoder info, etc.).

## Por que estas decisiones

### MP3 256kbps CBR

- Maxima compatibilidad con estereos de auto
- CBR es mas estable para decodificadores viejos que VBR
- 256kbps es transparente para la mayoria de los oyentes
- Ahorra espacio vs FLAC (~4-5x menos)

### Highpass a 100 Hz

Los parlantes de auto no reproducen frecuencias por debajo de ~80-100 Hz. Eliminarlas ahorra bitrate que se desperdiciaria en informacion inaudible.

### Loudnorm two-pass

Cada album/cancion tiene un nivel de mastering diferente. Sin normalizacion, hay que ajustar el volumen manualmente entre temas. El two-pass de loudnorm mide primero el loudness real de cada archivo y luego aplica la correccion exacta para que todo suene al mismo volumen percibido.

### fatsort

Sin fatsort, el estereo lee los archivos en el orden en que fueron escritos al sistema de archivos FAT, que depende del filesystem y no del nombre. Esto hace que las canciones suenen en orden aleatorio. `fatsort` reordena las entradas del directorio fisicamente en el dispositivo para que coincidan con el orden alfabetico.

### Solo stream de audio (-map 0:a)

Los FLAC suelen tener imagenes de portada embedidas como streams de video. Sin `-map 0:a`, ffmpeg las incluiria en el MP3 como imagenes PNG/JPEG embedidas, inflando el archivo innecesariamente.

## Consideraciones

- FAT32 tiene limite de 4GB por archivo (no aplica para MP3)
- No superar ~500-600 archivos por carpeta para evitar problemas en estereos viejos
- Mantener un solo nivel de directorios (carpetas de album, sin subcarpetas)
- Nombres de archivo/carpeta maximo 64 caracteres para compatibilidad
- Si se agregan o eliminan archivos en el futuro, volver a correr `fatsort`

## Log

Cada ejecucion genera un `processing.log` en el directorio destino con el detalle de cada archivo procesado.

## Licencia

Personal. Uso libre.
