<?php
$pageTitle = "Console MySQL";
$currentTime = date("H:i:s");

$defaults = [
    "host" => "192.168.20.12",
    "port" => "3306",
    "db" => "",
    "user" => "",
    "query" => "SELECT 1"
];

$errors = [];
$rows = [];
$columns = [];
$rowCount = 0;
$executedQuery = "";

$host = $defaults["host"];
$port = $defaults["port"];
$db = $defaults["db"];
$user = $defaults["user"];
$pass = "";
$query = $defaults["query"];

if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $host = trim($_POST["host"] ?? $defaults["host"]);
    $port = trim($_POST["port"] ?? $defaults["port"]);
    $db = trim($_POST["db"] ?? "");
    $user = trim($_POST["user"] ?? "");
    $pass = $_POST["pass"] ?? "";
    $query = trim($_POST["query"] ?? "");

    if ($host === "" || $port === "" || $db === "" || $user === "" || $query === "") {
        $errors[] = "Tous les champs sont requis sauf le mot de passe si l'utilisateur n'en a pas.";
    }

    if ($query !== "" && !preg_match('/^\s*select\b/i', $query)) {
        $errors[] = "Seules les requetes SELECT sont autorisees.";
    }

    if (empty($errors)) {
        if (!preg_match('/\blimit\b/i', $query)) {
            $query .= " LIMIT 100";
        }
        $executedQuery = $query;

        $portNumber = (int) $port;
        $conn = @new mysqli($host, $user, $pass, $db, $portNumber);
        if ($conn->connect_error) {
            $errors[] = "Connexion MySQL echouee: " . $conn->connect_error;
        } else {
            $conn->set_charset("utf8mb4");
            $result = $conn->query($query);
            if ($result === false) {
                $errors[] = "Erreur SQL: " . $conn->error;
            } elseif ($result instanceof mysqli_result) {
                $fields = $result->fetch_fields();
                foreach ($fields as $field) {
                    $columns[] = $field->name;
                }
                $rows = $result->fetch_all(MYSQLI_ASSOC);
                $rowCount = count($rows);
                $result->free();
            }
            $conn->close();
        }
    }
}

function esc($value) {
    return htmlspecialchars((string) $value, ENT_QUOTES, "UTF-8");
}
?>
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?php echo esc($pageTitle); ?></title>
    <style>
        @import url('https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600&family=Playfair+Display:wght@600&display=swap');
        :root {
            --ink: #0f172a;
            --muted: #64748b;
            --accent: #0ea5a8;
            --accent-2: #f97316;
            --paper: #f8fafc;
            --card: #ffffff;
            --shadow: 0 24px 60px rgba(15, 23, 42, 0.18);
        }
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Space Grotesk', Arial, sans-serif;
            color: var(--ink);
            background: radial-gradient(circle at top, #e0f2fe 0%, #ecfeff 35%, #fff7ed 100%);
            min-height: 100vh;
            padding: 48px 20px 80px;
        }
        .page {
            max-width: 980px;
            margin: 0 auto;
            display: grid;
            gap: 28px;
        }
        header {
            display: flex;
            flex-direction: column;
            gap: 10px;
        }
        h1 {
            font-family: 'Playfair Display', 'Times New Roman', serif;
            font-size: clamp(2.2rem, 3vw, 3.2rem);
            letter-spacing: -0.02em;
        }
        .subtitle {
            color: var(--muted);
            font-size: 1.05rem;
        }
        .grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
            gap: 18px;
        }
        .card {
            background: var(--card);
            border-radius: 16px;
            padding: 22px;
            box-shadow: var(--shadow);
        }
        .badge {
            display: inline-flex;
            align-items: center;
            gap: 8px;
            background: rgba(14, 165, 168, 0.12);
            color: var(--accent);
            font-weight: 600;
            padding: 6px 12px;
            border-radius: 999px;
            font-size: 0.85rem;
        }
        .time {
            font-size: 1.1rem;
            margin-top: 10px;
            color: var(--muted);
        }
        form {
            display: grid;
            gap: 16px;
        }
        label {
            font-weight: 600;
            font-size: 0.95rem;
        }
        .field {
            display: grid;
            gap: 8px;
        }
        input,
        textarea {
            width: 100%;
            padding: 12px 14px;
            border-radius: 12px;
            border: 1px solid #e2e8f0;
            font-size: 0.98rem;
            background: #f8fafc;
        }
        textarea {
            min-height: 130px;
            resize: vertical;
            font-family: 'Space Grotesk', Arial, sans-serif;
        }
        .button {
            border: none;
            background: linear-gradient(135deg, var(--accent), var(--accent-2));
            color: white;
            padding: 12px 20px;
            border-radius: 12px;
            font-weight: 600;
            font-size: 1rem;
            cursor: pointer;
            transition: transform 0.15s ease, box-shadow 0.2s ease;
        }
        .button:hover {
            transform: translateY(-2px);
            box-shadow: 0 14px 30px rgba(14, 165, 168, 0.3);
        }
        .note {
            font-size: 0.9rem;
            color: var(--muted);
        }
        .errors {
            background: #fee2e2;
            color: #991b1b;
            padding: 14px;
            border-radius: 12px;
            display: grid;
            gap: 6px;
        }
        .results {
            display: grid;
            gap: 12px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 0.95rem;
            overflow: hidden;
            border-radius: 12px;
        }
        th,
        td {
            padding: 10px 12px;
            border-bottom: 1px solid #e2e8f0;
            text-align: left;
        }
        th {
            background: #f1f5f9;
            font-weight: 600;
        }
        .empty {
            padding: 12px;
            background: #fef3c7;
            border-radius: 12px;
            color: #92400e;
        }
        @media (max-width: 640px) {
            body {
                padding: 28px 16px 60px;
            }
        }
    </style>
</head>
<body>
    <div class="page">
        <header>
            <span class="badge">Serveur MySQL: 192.168.20.12</span>
            <h1><?php echo esc($pageTitle); ?></h1>
            <p class="subtitle">Execute des requetes SELECT et visualise les resultats en direct.</p>
            <div class="time">Heure serveur: <?php echo esc($currentTime); ?></div>
        </header>

        <div class="grid">
            <section class="card">
                <form method="post">
                    <div class="field">
                        <label for="host">Hote MySQL</label>
                        <input id="host" name="host" type="text" value="<?php echo esc($host); ?>" required>
                    </div>
                    <div class="field">
                        <label for="port">Port</label>
                        <input id="port" name="port" type="text" value="<?php echo esc($port); ?>" required>
                    </div>
                    <div class="field">
                        <label for="db">Base de donnees</label>
                        <input id="db" name="db" type="text" value="<?php echo esc($db); ?>" required>
                    </div>
                    <div class="field">
                        <label for="user">Utilisateur</label>
                        <input id="user" name="user" type="text" value="<?php echo esc($user); ?>" required>
                    </div>
                    <div class="field">
                        <label for="pass">Mot de passe</label>
                        <input id="pass" name="pass" type="password" value="" autocomplete="current-password">
                    </div>
                    <div class="field">
                        <label for="query">Requete SELECT</label>
                        <textarea id="query" name="query" required><?php echo esc($query); ?></textarea>
                    </div>
                    <button class="button" type="submit">Executer la requete</button>
                    <p class="note">Une limite de 100 lignes est appliquee si elle n'est pas fournie.</p>
                </form>
            </section>

            <section class="card results">
                <h2>Resultats</h2>
                <?php if (!empty($errors)) { ?>
                    <div class="errors">
                        <?php foreach ($errors as $error) { ?>
                            <div><?php echo esc($error); ?></div>
                        <?php } ?>
                    </div>
                <?php } elseif ($_SERVER["REQUEST_METHOD"] === "POST") { ?>
                    <?php if ($executedQuery !== "") { ?>
                        <p class="note">Requete executee: <?php echo esc($executedQuery); ?></p>
                    <?php } ?>
                    <?php if ($rowCount === 0) { ?>
                        <div class="empty">Aucune ligne retournee.</div>
                    <?php } else { ?>
                        <div class="note"><?php echo esc($rowCount); ?> lignes affichees.</div>
                        <table>
                            <thead>
                                <tr>
                                    <?php foreach ($columns as $column) { ?>
                                        <th><?php echo esc($column); ?></th>
                                    <?php } ?>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($rows as $row) { ?>
                                    <tr>
                                        <?php foreach ($columns as $column) { ?>
                                            <td><?php echo esc($row[$column] ?? ""); ?></td>
                                        <?php } ?>
                                    </tr>
                                <?php } ?>
                            </tbody>
                        </table>
                    <?php } ?>
                <?php } else { ?>
                    <p class="note">Remplis le formulaire pour lancer une requete SELECT.</p>
                <?php } ?>
            </section>
        </div>
    </div>
</body>
</html>