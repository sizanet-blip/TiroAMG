# Herramientas locales (Windows)

## nuget.exe

El plugin `audioplayers` en Windows necesita **NuGet** para instalar
`Microsoft.Windows.ImplementationLibrary`.

Si `flutter run -d windows` falla con:

```text
Failed to install nuget package Microsoft.Windows.ImplementationLibrary...
```

1. Descarga: https://dist.nuget.org/win-x86-commandline/v6.5.0/nuget.exe
2. Guárdalo aquí como `tools/nuget.exe`
3. Añade esta carpeta `tools` al PATH de Windows (usuario)
4. Cierra y abre la terminal, luego:

```powershell
flutter clean
flutter run -d windows
```
