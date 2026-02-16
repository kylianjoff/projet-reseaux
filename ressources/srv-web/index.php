<?php
$pageTitle = "Bienvenue";
$currentTime = date("H:i:s");
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo $pageTitle; ?></title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
            text-align: center;
            max-width: 500px;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        p {
            color: #666;
            font-size: 16px;
            margin: 15px 0;
        }
        .time {
            background: #f0f0f0;
            padding: 15px;
            border-radius: 5px;
            font-weight: bold;
            color: #667eea;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1><?php echo $pageTitle; ?></h1>
        <p>Ceci est une petite page web générée en PHP.</p>
        <p>Cette page affiche l'heure actuelle du serveur.</p>
        <div class="time">
            Heure: <?php echo $currentTime; ?>
        </div>
    </div>
</body>
</html>