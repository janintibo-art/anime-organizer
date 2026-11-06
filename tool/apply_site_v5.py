#!/usr/bin/env python3
"""Ajoute une galerie demonstrative sans remplacer les autres sections du site."""
from pathlib import Path
root=Path(__file__).resolve().parents[1]
page=root/'docs'/'index.html'
if not page.is_file():raise SystemExit('ERREUR : docs/index.html est introuvable')
s=page.read_text(encoding='utf-8')
if 'id="apercus"' in s:
 print('Galerie deja presente : aucun doublon ajoute.')
 raise SystemExit(0)
if '<section id="fonctionnalites"' not in s or '</style>' not in s:
 raise SystemExit('Version du site differente : aucune modification appliquee.')
css='''
/* V5 : galerie demonstrative fidele a la version Windows */
.preview-area{padding:74px 0 68px;border-top:1px solid #ffffff12;background:linear-gradient(145deg,#121820,#1e181a 65%,#0e1218)}
.preview-head{max-width:790px}.preview-grid{display:grid;grid-template-columns:1fr 1fr;gap:23px;margin-top:30px}
.preview-frame{display:block;background:#16191c;border:1px solid #42464a;border-radius:12px;overflow:hidden;box-shadow:0 20px 55px #0007;transition:transform .18s,border-color .18s}
.preview-frame:hover{transform:translateY(-4px);border-color:#dc564f}.preview-frame img{display:block;width:100%;height:auto;aspect-ratio:1.8;object-fit:cover}
.preview-meta{padding:17px 19px}.preview-meta strong{display:block;font-size:17px}.preview-meta span{font-size:13px;color:#b9c0c6}
.preview-hint{font-size:13px;color:#c4c6ca;margin-top:17px}.preview-bullet{color:#ff746a;font-weight:700}
@media(max-width:750px){.preview-grid{grid-template-columns:1fr}.preview-area{padding:52px 0}.preview-frame img{aspect-ratio:auto}}
'''
section='''
<section id="apercus" class="preview-area">
 <div class="wrap">
  <div class="preview-head"><div class="eyebrow">Dans l'application</div>
  <h2>Découvre l'interface avant d'installer.</h2>
  <p>Une bibliothèque claire pour parcourir tes animations et des fiches immersives pour retrouver chaque épisode, directement sur ton appareil.</p></div>
  <div class="preview-grid">
   <a class="preview-frame" href="assets/apercu_bibliotheque.webp" target="_blank" rel="noopener" aria-label="Agrandir la vue bibliothèque de démonstration">
    <img src="assets/apercu_bibliotheque.webp" loading="lazy" width="1440" height="800" alt="Reconstitution de l'application Windows : grille d'affiches, filtres et noms de séries fictifs" />
    <div class="preview-meta"><strong>La bibliothèque</strong><span>Affiches, filtres, catégories, recherche et favoris · Agrandir l'image</span></div>
   </a>
   <a class="preview-frame" href="assets/apercu_fiche.webp" target="_blank" rel="noopener" aria-label="Agrandir la fiche de démonstration">
    <img src="assets/apercu_fiche.webp" loading="lazy" width="1440" height="800" alt="Reconstitution de l'application Windows : fiche fictive avec image en arrière-plan, synopsis et épisodes" />
    <div class="preview-meta"><strong>La fiche détaillée</strong><span>Fond panoramique, synopsis, progression et liste des épisodes · Agrandir l'image</span></div>
   </a>
  </div>
  <p class="preview-hint"><span class="preview-bullet">● Démonstration visuelle</span> — Illustrations et titres inventés. Ces visuels reproduisent l'organisation générale de l'interface Windows ; certaines options peuvent varier selon la version.</p>
 </div>
</section>
'''
s=s.replace('</style>',css+'</style>',1)
s=s.replace('<section id="fonctionnalites"',section+'<section id="fonctionnalites"',1)
s=s.replace('href="#fonctionnalites">Découvrir les fonctions','href="#apercus">Voir l’application',1)
s=s.replace('<a href="#fonctionnalites">Fonctionnalités</a>','<a href="#apercus">Aperçus</a><a href="#fonctionnalites">Fonctionnalités</a>',1)
page.write_text(s,encoding='utf-8')
print('Galerie V5 ajoutee a docs/index.html')
