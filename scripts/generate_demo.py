"""Original illustrative demo. Synthetic text only; not a recording or benchmark."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math

out = Path(__file__).resolve().parents[1]/'docs/assets'
out.mkdir(parents=True, exist_ok=True)
font = '/System/Library/Fonts/Supplemental/Arial.ttf'
bold = '/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def f(n, heavy=False): return ImageFont.truetype(bold if heavy else font, n)
def base():
 im=Image.new('RGB',(1200,660),'#0d0918'); d=ImageDraw.Draw(im)
 for y in range(660):
  c=int(12*math.sin(y/660*math.pi));d.line((0,y,1200,y),fill=(13+c,9,24+c*2))
 return im,d
im,d=base()
d.text((76,65),'PULSE / COMUNIDADE',font=f(22,True),fill='#c4a7ff')
d.text((72,154),'Fale.',font=f(112,True),fill='#faf7ff')
d.text((72,273),'O texto acompanha.',font=f(76,True),fill='#faf7ff')
d.text((78,415),'Ditado em português, no seu Mac.',font=f(31),fill='#c0b4d4')
d.rounded_rectangle((76,513,432,575),20,fill='#a982fa')
d.text((102,532),'Gratuito. Local. Aberto.',font=f(24,True),fill='#160d27')
for i in range(18):
 h=20+80*math.sin(i*0.63)**2
 d.rounded_rectangle((790+i*17,523-h/2,798+i*17,523+h/2),4,fill='#c4a7ff')
im.save(out/'hero.png',optimize=True)
text='Olá, equipe. Vamos organizar as ideias\ne combinar os próximos passos.'
frames=[]
for frame in range(64):
 im,d=base()
 d.text((62,35),'PULSE',font=f(24,True),fill='#c4a7ff')
 d.text((774,40),'DEMONSTRAÇÃO ILUSTRATIVA',font=f(16),fill='#b7aaca')
 d.text((62,95),'Sua ideia vira texto.',font=f(48,True),fill='#faf7ff')
 d.rounded_rectangle((60,185,1140,485),22,fill='#f8f5fc')
 d.ellipse((84,205,96,217),fill='#c4b2d5');d.ellipse((106,205,118,217),fill='#c4b2d5');d.ellipse((128,205,140,217),fill='#c4b2d5')
 d.text((172,201),'Um rascunho, sem digitar',font=f(18),fill='#62536f')
 portion=text[:min(len(text),max(0,int((frame-6)*len(text)/40)))]
 d.multiline_text((92,280),portion+('▏' if frame<54 else ''),font=f(34),fill='#291b3b',spacing=20)
 d.rounded_rectangle((324,515,876,610),28,fill='#281941',outline='#69489b',width=2)
 for i in range(30):
  h=8+(33*abs(math.sin(i*.7+frame*.45)) if 6<frame<49 else 4)
  d.rounded_rectangle((352+i*7,560-h/2,356+i*7,560+h/2),2,fill='#c5a3ff')
 d.text((595,547),'Tempo real' if frame<54 else 'Pronto para revisar',font=f(22),fill='#f4edff')
 frames.append(im.resize((900,495),Image.Resampling.LANCZOS))
frames[-1].save(out/'demo.png',optimize=True)
frames[0].save(out/'demo.gif',save_all=True,append_images=frames[1:],duration=[110]*63+[1800],loop=0,optimize=True)
print('Hero, illustrative GIF and static fallback generated')
