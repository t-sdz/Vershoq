import random
import time

def jeu_pierre_papier_ciseaux():
    choix_possibles = ['pierre', 'papier', 'ciseaux']
    
    # Initialiser les compteurs
    manches_jouees = 0
    victoires_joueur = 0
    victoires_ordinateur = 0
    egalites = 0
    
    while True:
        # Choix aléatoire pour le joueur et l'ordinateur
        joueur = random.choice(choix_possibles)
        ordinateur = random.choice(choix_possibles)

        print(f"Manche {manches_jouees + 1}:")
        print(f"Le joueur a choisi {joueur}, l'ordinateur a choisi {ordinateur}.")

        if joueur == ordinateur:
            print("Égalité!")
            egalites += 1
        elif (joueur == 'pierre' and ordinateur == 'ciseaux') or \
             (joueur == 'papier' and ordinateur == 'pierre') or \
             (joueur == 'ciseaux' and ordinateur == 'papier'):
            print("Le joueur gagne!")
            victoires_joueur += 1
        else:
            print("L'ordinateur gagne!")
            victoires_ordinateur += 1

        manches_jouees += 1

        # Attendre brièvement avant la manche suivante pour une boucle rapide
        time.sleep(0.1)

        # Arrêter après un nombre défini de manches ou en appuyant sur une touche
        if manches_jouees >= 100:  # Changez ce nombre pour plus ou moins de manches
            break

    # Affichage des résultats finaux
    print("\n--- Résultats finaux ---")
    print(f"Manches jouées : {manches_jouees}")
    print(f"Victoires du joueur : {victoires_joueur}")
    print(f"Victoires de l'ordinateur : {victoires_ordinateur}")
    print(f"Égalités : {egalites}")
    print("Merci d'avoir joué !")

# Lancement du jeu
jeu_pierre_papier_ciseaux()
