import Foundation

/// The built-in knowledge behind `SymbolResolver`: the commands every Mac app shares, verbs, keywords and menu names,
/// in English and French. Keys are already normalized (lowercase, no accents, no ellipsis) because lookups normalize
/// the title the same way.
enum StandardCommandSymbols {
    /// Shortcuts that mean the same thing in every Mac app, as printed in menus. Ones that differ between apps
    /// (Command-B is Bold in a text editor and Build in Xcode) are deliberately absent.
    static let shortcuts: [String: String] = [
        "⌘N": "plus", "⌘O": "folder", "⌘W": "xmark", "⌘S": "square.and.arrow.down",
        "⇧⌘S": "square.and.arrow.down.on.square", "⌘P": "printer", "⌘Z": "arrow.uturn.backward",
        "⇧⌘Z": "arrow.uturn.forward", "⌘X": "scissors", "⌘C": "doc.on.doc", "⌘V": "doc.on.clipboard",
        "⌘A": "selection.pin.in.out", "⌘F": "magnifyingglass", "⌘,": "gearshape", "⌘Q": "power", "⌘H": "eye.slash",
        "⌘M": "minus.rectangle",
    ]

    /// Whole titles of standard commands.
    static let titles: [String: String] = [
        "undo": "arrow.uturn.backward", "annuler": "arrow.uturn.backward",
        "redo": "arrow.uturn.forward", "retablir": "arrow.uturn.forward",
        "cut": "scissors", "couper": "scissors",
        "copy": "doc.on.doc", "copier": "doc.on.doc",
        "paste": "doc.on.clipboard", "coller": "doc.on.clipboard",
        "paste and match style": "doc.on.clipboard.fill", "coller en adaptant le style": "doc.on.clipboard.fill",
        "select all": "selection.pin.in.out", "tout selectionner": "selection.pin.in.out",
        "delete": "trash", "supprimer": "trash",
        "find": "magnifyingglass", "rechercher": "magnifyingglass",
        "find next": "chevron.down", "occurrence suivante": "chevron.down",
        "find previous": "chevron.up", "occurrence precedente": "chevron.up",
        "close": "xmark", "fermer": "xmark",
        "close window": "xmark.square", "fermer la fenetre": "xmark.square",
        "close all": "xmark.square.fill", "tout fermer": "xmark.square.fill",
        "save": "square.and.arrow.down", "enregistrer": "square.and.arrow.down",
        "save as": "square.and.arrow.down.on.square", "enregistrer sous": "square.and.arrow.down.on.square",
        "duplicate": "plus.square.on.square", "dupliquer": "plus.square.on.square",
        "print": "printer", "imprimer": "printer",
        "minimize": "minus.rectangle", "reduire": "minus.rectangle",
        "zoom": "arrow.up.left.and.arrow.down.right", "agrandir": "arrow.up.left.and.arrow.down.right",
        "bring all to front": "square.3.layers.3d.top.filled",
        "tout ramener au premier plan": "square.3.layers.3d.top.filled",
        "enter full screen": "arrow.up.left.and.arrow.down.right",
        "passer en plein ecran": "arrow.up.left.and.arrow.down.right",
        "exit full screen": "arrow.down.right.and.arrow.up.left",
        "quitter le plein ecran": "arrow.down.right.and.arrow.up.left",
        "show toolbar": "menubar.rectangle", "hide toolbar": "menubar.rectangle",
        "afficher la barre d'outils": "menubar.rectangle", "masquer la barre d'outils": "menubar.rectangle",
        "show sidebar": "sidebar.left", "hide sidebar": "sidebar.left",
        "afficher la barre laterale": "sidebar.left", "masquer la barre laterale": "sidebar.left",
        "settings": "gearshape", "preferences": "gearshape", "parametres": "gearshape", "reglages": "gearshape",
        "services": "gearshape.2", "help": "questionmark.circle", "aide": "questionmark.circle",
        "start dictation": "mic", "commencer la dictee": "mic",
        "emoji & symbols": "face.smiling", "emoji et symboles": "face.smiling",
    ]

    /// Leading verbs: the first word of the title.
    static let verbs: [String: String] = [
        "new": "plus", "nouveau": "plus", "nouvelle": "plus", "add": "plus", "ajouter": "plus", "create": "plus",
        "creer": "plus",
        "open": "folder", "ouvrir": "folder",
        "close": "xmark", "fermer": "xmark",
        "save": "square.and.arrow.down", "enregistrer": "square.and.arrow.down",
        "export": "square.and.arrow.up", "exporter": "square.and.arrow.up", "share": "square.and.arrow.up",
        "partager": "square.and.arrow.up",
        "import": "square.and.arrow.down.on.square", "importer": "square.and.arrow.down.on.square",
        "print": "printer", "imprimer": "printer",
        "copy": "doc.on.doc", "copier": "doc.on.doc",
        "cut": "scissors", "couper": "scissors",
        "paste": "doc.on.clipboard", "coller": "doc.on.clipboard",
        "undo": "arrow.uturn.backward", "annuler": "arrow.uturn.backward",
        "redo": "arrow.uturn.forward", "retablir": "arrow.uturn.forward",
        "find": "magnifyingglass", "search": "magnifyingglass", "rechercher": "magnifyingglass",
        "select": "selection.pin.in.out", "selectionner": "selection.pin.in.out",
        "delete": "trash", "supprimer": "trash", "remove": "minus.circle", "retirer": "minus.circle",
        "clear": "xmark.circle", "effacer": "xmark.circle", "empty": "trash.slash", "vider": "trash.slash",
        "duplicate": "plus.square.on.square", "dupliquer": "plus.square.on.square",
        "rename": "pencil", "renommer": "pencil", "edit": "pencil", "modifier": "pencil",
        "zoom": "plus.magnifyingglass", "reload": "arrow.clockwise", "refresh": "arrow.clockwise",
        "actualiser": "arrow.clockwise", "recharger": "arrow.clockwise", "update": "arrow.triangle.2.circlepath",
        "check": "arrow.triangle.2.circlepath", "sync": "arrow.triangle.2.circlepath",
        "quit": "power", "quitter": "power", "exit": "power",
        "hide": "eye.slash", "masquer": "eye.slash", "show": "eye", "afficher": "eye",
        "minimize": "minus.rectangle", "reduire": "minus.rectangle",
        "settings": "gearshape", "preferences": "gearshape", "parametres": "gearshape", "reglages": "gearshape",
        "about": "info.circle", "get": "info.circle", "obtenir": "info.circle",
        "bring": "square.3.layers.3d.top.filled", "send": "paperplane", "envoyer": "paperplane",
        "run": "play", "executer": "play", "start": "play", "play": "play", "lire": "play", "pause": "pause",
        "stop": "stop", "arreter": "stop", "build": "hammer", "compiler": "hammer",
        "test": "checkmark.seal", "tester": "checkmark.seal", "clean": "sparkles", "nettoyer": "sparkles",
        "back": "chevron.backward", "retour": "chevron.backward", "forward": "chevron.forward",
        "suivant": "chevron.forward", "previous": "chevron.up", "precedent": "chevron.up", "next": "chevron.down",
        "go": "arrow.right.circle", "aller": "arrow.right.circle", "move": "arrow.right.square",
        "deplacer": "arrow.right.square", "lock": "lock", "verrouiller": "lock", "unlock": "lock.open",
        "toggle": "switch.2", "basculer": "switch.2", "merge": "arrow.triangle.merge", "commit": "checkmark.circle",
        "push": "arrow.up.circle", "pull": "arrow.down.circle", "fetch": "arrow.down.circle",
        "download": "arrow.down.circle", "telecharger": "arrow.down.circle", "upload": "arrow.up.circle",
        "sign": "signature", "log": "person.crop.circle", "connect": "link", "connecter": "link",
        "bookmark": "bookmark", "compress": "doc.zipper", "compresser": "doc.zipper", "reset": "arrow.counterclockwise",
        "reinitialiser": "arrow.counterclockwise", "restore": "arrow.counterclockwise",
        "restaurer": "arrow.counterclockwise", "customize": "slider.horizontal.3",
        "personnaliser": "slider.horizontal.3", "sort": "arrow.up.arrow.down", "trier": "arrow.up.arrow.down",
        "arrange": "square.grid.2x2", "organiser": "square.grid.2x2", "enter": "arrow.up.left.and.arrow.down.right",
    ]

    /// Words anywhere in the title, matched as whole words, for titles whose first word says little ("Toggle Sidebar").
    static let keywords: [String: String] = [
        "sidebar": "sidebar.left", "inspector": "sidebar.right", "inspecteur": "sidebar.right",
        "toolbar": "menubar.rectangle", "window": "macwindow", "fenetre": "macwindow", "tab": "rectangle.stack",
        "onglet": "rectangle.stack", "folder": "folder", "dossier": "folder", "file": "doc", "fichier": "doc",
        "history": "clock", "historique": "clock", "bookmarks": "bookmark", "signets": "bookmark", "font": "textformat",
        "police": "textformat", "bold": "bold", "gras": "bold", "italic": "italic", "italique": "italic",
        "underline": "underline", "souligne": "underline", "link": "link", "lien": "link", "image": "photo",
        "photo": "photo", "table": "tablecells", "tableau": "tablecells", "comment": "text.bubble",
        "commentaire": "text.bubble", "spelling": "textformat.abc", "orthographe": "textformat.abc",
        "debug": "ladybug", "debugger": "ladybug", "console": "terminal", "terminal": "terminal", "source": "arrow.triangle.branch",
        "branch": "arrow.triangle.branch", "branche": "arrow.triangle.branch", "password": "key", "passwords": "key",
        "mot de passe": "key", "printer": "printer", "update": "arrow.triangle.2.circlepath",
        "updates": "arrow.triangle.2.circlepath", "mises": "arrow.triangle.2.circlepath", "account": "person.crop.circle",
        "compte": "person.crop.circle", "notification": "bell", "notifications": "bell", "full": "arrow.up.left.and.arrow.down.right",
        "screen": "display", "ecran": "display", "trash": "trash", "corbeille": "trash",
    ]

    /// The top-level menu a command lives in.
    static let groups: [String: String] = [
        "file": "doc", "fichier": "doc", "edit": "pencil", "edition": "pencil", "view": "eye", "presentation": "eye",
        "affichage": "eye", "window": "macwindow", "fenetre": "macwindow", "help": "questionmark.circle",
        "aide": "questionmark.circle", "format": "textformat", "go": "arrow.right.circle", "aller": "arrow.right.circle",
        "history": "clock", "historique": "clock", "bookmarks": "bookmark", "signets": "bookmark",
        "product": "hammer", "produit": "hammer", "navigate": "location", "navigation": "location",
        "editor": "chevron.left.forwardslash.chevron.right", "editeur": "chevron.left.forwardslash.chevron.right",
        "insert": "plus.square", "insertion": "plus.square", "arrange": "square.3.layers.3d", "organiser": "square.3.layers.3d",
        "object": "cube", "objet": "cube", "text": "textformat", "texte": "textformat", "tab": "rectangle.stack",
        "onglet": "rectangle.stack", "develop": "wrench.and.screwdriver", "developpement": "wrench.and.screwdriver",
        "debug": "ladybug", "deboguer": "ladybug", "source control": "arrow.triangle.branch",
        "gestion des sources": "arrow.triangle.branch", "mailbox": "tray", "boite": "tray", "message": "bubble.left",
        "conversation": "bubble.left", "account": "person.crop.circle", "compte": "person.crop.circle",
        "playback": "play", "lecture": "play", "controls": "slider.horizontal.3", "commandes": "slider.horizontal.3",
        "song": "music.note", "morceau": "music.note", "sketch": "pencil.and.outline", "tools": "wrench.and.screwdriver",
        "outils": "wrench.and.screwdriver", "share": "square.and.arrow.up", "partage": "square.and.arrow.up",
    ]

    /// Last-resort symbols, tried in order when everything better is already used by a neighbour.
    static let spare = ["command", "square.dashed"]
}
