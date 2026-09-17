"""Versioned synthetic regression corpus; IDs are fixture IDs, not Deezer IDs."""
import json
from pathlib import Path

pairs = [
('Q&A', 'Drake'), ("Don't You (Forget About Me)", 'Simple Minds'),
('Sweet Dreams (Are Made of This)', 'Eurythmics'), ('The Motion', 'Drake'),
('INTRO', 'Damso'), ('Nés', 'NeS'), ('Shape of You', 'Ed Sheeran'),
('God’s Menu', 'Stray Kids'), ('Back In Black', 'AC/DC'), ('Gata Only', 'Cris MJ'),
('Si Veo a Tu Mamá', 'Bad Bunny'), ('A Tu Merced', 'Bad Bunny'),
('Désenchantée', 'Mylène Farmer'), ('Déjà Vu', 'Beyoncé'), ('Despechá', 'ROSALÍA'),
('Feu de bois', 'Damso'), ('Blinding Lights', 'The Weeknd'), ('Hello', 'Adele'),
('Hello', 'Lionel Richie'), ('Hello', 'Martin Solveig'), ('HUMBLE.', 'Kendrick Lamar'),
('Lose Yourself', 'Eminem'), ('Take On Me', 'a-ha'), ('Do It', 'Nelly Furtado'),
('Beautiful Day', 'U2'), ('Feel Good Inc.', 'Gorillaz'), ('Satisfaction', 'The Rolling Stones'),
('Paint It, Black', 'The Rolling Stones'), ('505', 'Arctic Monkeys'),
('Billie Jean', 'Michael Jackson'), ('Get Lucky (feat. Pharrell Williams)', 'Daft Punk'),
('Empire State of Mind', 'JAY-Z & Alicia Keys'), ('See You Again', 'Tyler, The Creator'),
('Звезда по имени Солнце', 'Кино'), ('群青', 'YOASOBI'), ('봄날', '방탄소년단'),
('Dernière danse', 'Indila'), ('La vie en rose', 'Édith Piaf'), ('Voilà', 'Barbara Pravi'),
('Tous les mêmes', 'Stromae'), ('Formidable', 'Stromae'), ('Alors on danse', 'Stromae'),
('L’amour toujours', 'Gigi D’Agostino'), ('Enjoy the Silence', 'Depeche Mode'),
('Nothing Else Matters', 'Metallica'), ('Wonderwall', 'Oasis'), ('One More Time', 'Daft Punk'),
('Bohemian Rhapsody', 'Queen'), ('Somebody to Love', 'Queen'), ('I Want to Break Free', 'Queen'),
]
docs = [dict(id=str(i+1), title=t, artist=a, rank=500000, artist_id=str(1+[x[1] for x in pairs].index(a))) for i,(t,a) in enumerate(pairs)]
queries = []
for i,d in enumerate(docs):
    t,a = d['title'],d['artist']
    variants = [('exact',t), ('title_artist',t+' '+a), ('artist',a), ('prefix',t[:max(2,len(t)//2)]), ('prefix',t[:max(2,len(t)-2)]), ('spacing',a.replace(' ',''))]
    for category,q in variants:
        expected = [x['id'] for x in docs if x['artist']==a] if category in ('artist','spacing') else [d['id']]
        queries.append(dict(query=q,kind='tracks',category=category,expected=expected,split='validation' if i%4==0 else 'tuning', max_rank=5 if category in ('title_artist','artist') or (category=='exact' and t not in ('INTRO','Hello')) else 20))
queries.extend(dict(query=q,kind='tracks',category='regression',expected=[str(i)],split='validation',max_rank=r) for q,i,r in [('q&a',1,1),('motion',4,5),('intro damso',5,5),('nes',6,5),('ed sheran',7,5),('straykids',8,5),('ac dc',9,5),('cris mj',10,5),('si veo a tu mama',11,5),('a tu merced',12,5)])
# High-popularity distractors make pre-ranking candidate truncation observable.
for i in range(220):
    docs.append(dict(id=str(1000+i), title=f'Theme {i} (From the Motion Picture Soundtrack)', artist=f'Orchestra {i}',artist_id=str(1000+i),rank=990000))
for i in range(10):
    docs.append(dict(id=str(2000+i),title='INTRO',artist=f'Other artist {i}',artist_id=str(2000+i),rank=800000))
# Same spelling, different artist entities must remain separate.
docs.extend([dict(id='3001',title='Hello',artist='Adele',artist_id='3001',rank=100),dict(id='3002',title='Hello (Remix)',artist='Adele',artist_id=docs[17]['artist_id'],rank=100)])
root=Path(__file__).resolve().parents[2]/'docs/search'
(root/'corpus.json').write_text(json.dumps(dict(schema=2, provenance='Synthetic fixtures; musical names only, no production export. Alphabet coverage is illustrative, not measured production coverage.', documents=docs,queries=queries),ensure_ascii=False,indent=2)+'\n')
