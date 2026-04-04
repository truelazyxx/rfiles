# Wymagane biblioteki WPF
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Pobranie JSON z GitHub
$jsonUrl = "https://raw.githubusercontent.com/truelazyxx/rfiles/main/files.json"
$json = Invoke-RestMethod -Uri $jsonUrl

# Ścieżka do katalogu skryptu i pliku zapamiętującego ostatnią ścieżkę
$basePath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$lastPathFile = Join-Path $basePath "lastpath.txt"
$lastPath = if (Test-Path $lastPathFile) { Get-Content $lastPathFile } else { "" }

# XAML dla GUI
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="RvSwapper" Width="1000" Height="730" Background="#1E1E1E"
        ResizeMode="NoResize">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="2*"/>
            <ColumnDefinition Width="3*"/>
        </Grid.ColumnDefinitions>

        <TextBox Name="PathText" Grid.ColumnSpan="2" Grid.Row="0" Height="30" Margin="0,0,0,10" Background="#2A2A2A" Foreground="White"/>

        <GroupBox Header="Textures" Grid.Row="1" Grid.Column="0" Margin="0,0,10,0">
            <ListBox Name="TexturesList" Background="#2A2A2A" Foreground="White"/>
        </GroupBox>

        <GroupBox Header="Skyboxes" Grid.Row="1" Grid.Column="1">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="2*"/>
                    <RowDefinition Height="3*"/>
                </Grid.RowDefinitions>
                <ListBox Name="SkyboxList" Background="#2A2A2A" Foreground="White"/>
                <Border Grid.Row="1" Background="#111" CornerRadius="8" Margin="5">
                    <Image Name="PreviewImage" Stretch="Uniform"/>
                </Border>
            </Grid>
        </GroupBox>

        <StackPanel Grid.Row="2" Grid.ColumnSpan="2" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,10,0,0">
            <Button Name="ApplyTextures" Content="Apply Textures" Width="140" Height="35" Margin="5" Background="#3A3A3A" Foreground="White"/>
            <Button Name="ApplySkybox" Content="Apply Skybox" Width="140" Height="35" Margin="5" Background="#3A3A3A" Foreground="White"/>
            <Button Name="SkyboxFix" Content="Skybox Fix" Width="140" Height="35" Margin="5" Background="#3A3A3A" Foreground="White"/>
        </StackPanel>

        <Border Grid.Row="3" Grid.ColumnSpan="2" Height="25" CornerRadius="8" Background="#2A2A2A" BorderBrush="#3A3A3A" BorderThickness="1" Margin="10,10,10,0">
            <ProgressBar Name="ProgressBar" Minimum="0" Maximum="100" Value="0" Foreground="#4CAF50" Background="#2A2A2A"/>
        </Border>
    </Grid>
</Window>
"@

# Załaduj XAML
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Pobierz kontrolki
$PathText = $window.FindName("PathText")
$TexturesList = $window.FindName("TexturesList")
$SkyboxList = $window.FindName("SkyboxList")
$PreviewImage = $window.FindName("PreviewImage")
$ApplyTextures = $window.FindName("ApplyTextures")
$ApplySkybox = $window.FindName("ApplySkybox")
$SkyboxFixButton = $window.FindName("SkyboxFix")
$ProgressBar = $window.FindName("ProgressBar")

# Ustaw ostatnią ścieżkę
$PathText.Text = $lastPath
$PathText.Add_TextChanged({ Set-Content -Path $lastPathFile -Value $PathText.Text })

# Wypełnij listy
$allTextures = ($json.textures | ForEach-Object { ($_ -split "/")[0] } | Sort-Object -Unique)
$allTextures | ForEach-Object { $TexturesList.Items.Add($_) | Out-Null }

$allSkyboxes = ($json.skybox | ForEach-Object { ($_ -split "/")[0] } | Sort-Object -Unique)
$allSkyboxes | ForEach-Object { $SkyboxList.Items.Add($_) | Out-Null }

# Podgląd skybox
$SkyboxList.Add_SelectionChanged({
    $selected = $SkyboxList.SelectedItem
    if ($selected) {
        $url = "https://raw.githubusercontent.com/truelazyxx/rfiles/main/PNGPreview/$selected.png"
        try {
            $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
            $bitmap.BeginInit()
            $bitmap.UriSource = [Uri]$url
            $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
            $bitmap.CreateOptions = [System.Windows.Media.Imaging.BitmapCreateOptions]::IgnoreColorProfile
            $bitmap.EndInit()
            $PreviewImage.Source = $bitmap
        } catch {
            $PreviewImage.Source = $null
        }
    }
})

# Funkcja instalacji tekstur (czyszczenie całego folderu)
function Install-Textures {
    param(
        [string]$PackageName,
        [string]$Destination
    )

    # Wyczyść folder docelowy
    if (Test-Path $Destination) {
        Get-ChildItem -Path $Destination -Recurse -Force | Remove-Item -Recurse -Force
    } else {
        New-Item -ItemType Directory -Path $Destination | Out-Null
    }

    $files = $json.textures | Where-Object { $_ -like "$PackageName/*" }

    $ProgressBar.Value = 0
    $ProgressBar.Maximum = $files.Count

    foreach ($file in $files) {
        $relativePath = $file -replace "^$PackageName/", ""
        $destPath = Join-Path $Destination $relativePath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        $url = "https://raw.githubusercontent.com/truelazyxx/rfiles/main/textures/$file"
        Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing

        $ProgressBar.Value += 1
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    [System.Windows.MessageBox]::Show("Textures $PackageName installed!")
    $ProgressBar.Value = 0
}

# Obsługa kliknięcia Apply Textures
$ApplyTextures.Add_Click({
    if (-not $PathText.Text) { [System.Windows.MessageBox]::Show("Enter path!"); return }
    if (-not $TexturesList.SelectedItem) { [System.Windows.MessageBox]::Show("Select textures!"); return }

    $texturesDest = $PathText.Text
    Install-Textures -PackageName $TexturesList.SelectedItem -Destination $texturesDest

    # Zapisanie stanu
    $assetsDir = Join-Path $basePath "assets"
    if (-not (Test-Path $assetsDir)) { New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null }
    $lastStateFile = Join-Path $assetsDir "last_state.txt"
    Set-Content -Path $lastStateFile -Value "Current_Textures = $($TexturesList.SelectedItem)`nCurrent_Skybox = $($SkyboxList.SelectedItem)"
})

# Obsługa Apply Skybox (czyszczenie tylko folderu sky)
$InstallingSkybox = $false
$ApplySkybox.Add_Click({
    if ($InstallingSkybox) { return }
    $InstallingSkybox = $true
    $ApplySkybox.IsEnabled = $false

    if (-not $PathText.Text) { [System.Windows.MessageBox]::Show("Enter path!"); $InstallingSkybox=$false; $ApplySkybox.IsEnabled=$true; return }
    if (-not $SkyboxList.SelectedItem) { [System.Windows.MessageBox]::Show("Select a skybox!"); $InstallingSkybox=$false; $ApplySkybox.IsEnabled=$true; return }

    $selected = $SkyboxList.SelectedItem
    $destSky = Join-Path $PathText.Text "sky"

    if (-not (Test-Path $destSky)) { New-Item -ItemType Directory -Path $destSky -Force | Out-Null }

    # Czyszczenie tylko folderu sky
    Get-ChildItem -Path $destSky -Recurse -Force | Remove-Item -Recurse -Force

    $files = $json.skybox | Where-Object { $_ -like "$selected/*" }

    $ProgressBar.Value = 0
    $ProgressBar.Maximum = $files.Count

    foreach ($file in $files) {
        $relativePath = $file -replace "^$selected/", ""
        $destPath = Join-Path $destSky $relativePath
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

        $url = "https://raw.githubusercontent.com/truelazyxx/rfiles/main/skybox/$file"
        try { Invoke-WebRequest -Uri $url -OutFile $destPath -UseBasicParsing }
        catch { Write-Warning "Nie udało się pobrać pliku: $file" }

        $ProgressBar.Value += 1
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }

    [System.Windows.MessageBox]::Show("Skybox installed!")
    $ProgressBar.Value = 0
    $InstallingSkybox = $false
    $ApplySkybox.IsEnabled = $true
})

# Obsługa SkyboxFix
$SkyboxFixButton.Add_Click({
    $batPath = Join-Path $basePath "assets\skyboxfix\move.bat"
    if (Test-Path $batPath) { Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$batPath`"" -WindowStyle Normal }
    else { [System.Windows.MessageBox]::Show("move.bat not found!") }
})

# Uruchomienie okna
$window.Topmost = $false
$window.ShowDialog() | Out-Null