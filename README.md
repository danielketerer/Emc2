# Da Matéria

Jogo incremental 2D em GDScript, validado no Godot 4.7.2 para Windows.

## Jogar

Abra `project.godot` no Godot e pressione F5. Para F6, abra `scenes/main.tscn`.

A distribuição Windows para download está em [dist/DaMateria-Windows.zip](dist/DaMateria-Windows.zip). Extraia o arquivo e execute `DaMateria.exe`.

A versão portátil local fica em `build/DaMateria.exe`. Mantenha `DaMateria.pck` ao lado do executável. O pacote usa o executável completo do Godot 4.7.2 disponível na máquina. As licenças do motor acompanham a distribuição.

## Abertura e evolução do meio

Um novo jogo começa com 0,65 segundo de tela inteiramente preta. Um pulso central se expande e libera uma nuvem de elétrons. Aos 2,8 segundos, o jogador assume o elétron mais luminoso no centro. Os primeiros prótons começam a aparecer aos 6,8 segundos, com surgimento gradual.

O fundo permanece preto nas três fases. As partículas visíveis pertencem à simulação. Prótons, átomos e H₂ se deslocam em torno de suas regiões de origem. Elétrons se aproximam dos prótons e se incorporam aos átomos. Quando o jogador chega à forma de hidrogênio, pares de átomos do ambiente também começam a se unir em H₂. As moléculas produzidas ficam disponíveis para coleta e cristalização.

A abertura aparece em novos jogos. R abre a confirmação para recomeçar e assistir à sequência. Ao continuar um save existente, o jogo restaura o ponto alcançado. A abertura em andamento também é salva e retomada.

## Controles e progressão

- Mova o mouse para conduzir a matéria. A distância do cursor regula a velocidade. Coloque o cursor sobre o jogador para parar.
- Clique no próton realçado para formar H. Clique em outro H realçado para formar H₂.
- Como H₂ livre, você pode atrair grupos de moléculas próximas. Elas ficam em órbita até chegar à superfície fria.
- Na superfície fria, o movimento desacelera. Aproxime-se de um dos três pontos junto às moléculas já depositadas e clique para incorporar seu próprio H₂ ao núcleo.
- Após a incorporação, o cursor seleciona posições livres que tocam a borda do cristal. A linha até um H₂ indica a molécula que será guiada até ali. Clique para acomodar o par inteiro.
- Cada animação termina com um pulso curto. A próxima colocação depende de outro clique. Você pode observar a estrutura pelo tempo que quiser.
- Esc abre a pausa, o volume e a redução de flashes. F11 alterna janela e tela cheia. R abre a confirmação de novo jogo.

## Do H₂ ao cristal

A superfície contém três pontos de nucleação, cada um com três moléculas previamente depositadas. O H₂ do jogador ocupa a posição escolhida e transfere o controle para a borda. As moléculas que o acompanhavam em órbita são liberadas perto do núcleo e continuam disponíveis para incorporação.

A rede usa coordenadas axiais em uma grade triangular com espaçamento de 86 unidades e fileiras alternadas. A borda é recalculada após cada encaixe. Cada posição recebe uma molécula inteira que esteja a até 400 unidades de seu destino.

Uma faixa larga pode alcançar os grupos distribuídos ao longo da superfície. Uma ponta estreita avança em direção aos bolsões da nuvem. Ambas as rotas chegam ao primeiro marco de 32 moléculas, incluindo as três depositadas e o H₂ do jogador. Outros cristais começam a crescer ao redor desse marco. O jogador pode continuar expandindo sua própria rede.

O enquadramento acompanha o núcleo em formação e depois recua conforme a extensão e o tamanho da rede. De perto, aparecem os pares luminosos e as fileiras desencontradas. À distância, o preenchimento e as bordas externas das mesmas células formam a silhueta facetada escolhida pelo jogador.

## Salvamento

O jogo continua automaticamente do progresso local. Salva após as transformações, ao iniciar e concluir incorporações, a cada 15 segundos e ao fechar a janela ou sair pelo menu.

O arquivo fica em `%APPDATA%/Godot/app_userdata/Da Matéria/matter_save.json`. As preferências ficam em `settings.cfg`. A gravação usa arquivo temporário e renomeação para concluir a atualização.

O formato atual também guarda o tempo da abertura, as posições e velocidades dos elétrons e as reações do ambiente. Elétrons ligados permanecem incorporados, e as moléculas coletadas ou reservadas pela rede permanecem fora da população livre.

O formato atual guarda a origem do núcleo, as coordenadas ocupadas, as moléculas incorporadas, os H₂ ainda disponíveis, o controle da borda e a animação em andamento. Uma incorporação interrompida ao fechar o jogo retoma com a mesma molécula reservada e o mesmo destino.

Os saves anteriores são convertidos ao carregar. O progresso da antiga rede fixa passa para a grade expansível. Um cristal já concluído na versão anterior conserva seu marco. Moléculas carregadas continuam disponíveis junto à estrutura.

## Gráficos leves e estrutura editável

- `scripts/universe.gd` simula a abertura, os elétrons e a formação da matéria em passos físicos. Os 1.024 elétrons ambientes são desenhados em um MultiMesh, com material compartilhado e posições interpoladas. O fundo preto usa uma superfície plana.
- `scripts/player.gd` separa o movimento físico da posição visual interpolada. A direção do mouse é medida em relação ao centro da tela.
- `scripts/crystal.gd` controla nucleação, borda, escolha de moléculas, animações, enquadramento e persistência da rede.
- `scripts/crystal_surface.gd` desenha as moléculas fixadas e o contorno das células. O desenho é atualizado quando a rede muda, com ajuste de detalhe ao recuar a câmera.
- `scripts/matter_visual.gd` compartilha o desenho de H₂ entre mapa, jogador, órbitas e moléculas em trânsito. Os detalhes e a frequência de redesenho diminuem à distância.
- `resources/*.tres` centralizam os parâmetros das formas e os materiais compartilhados.
- `scripts/world.gd` integra as regiões, interface, sons e salvamento.
- `scenes/visual_test.tscn` mantém o estudo de movimento e ligação, executável com F6.

Os prótons livres e os núcleos de H e H₂ usam a nuvem RGB pontilhada inspirada na referência fornecida. A representação esquemática indica dois quarks de valência up e um down envolvidos pela distribuição de quarks e glúons. RGB é uma convenção visual para carga de cor. Fontes disponíveis em [DOE — Protons](https://www.energy.gov/science/doe-explainsprotons) e [DOE — Quantum Chromodynamics](https://www.energy.gov/science/doe-explainsquantum-chromodynamics).

Cada próton usa um Sprite2D com ShaderMaterial e textura branca compartilhados. As moléculas já fixadas são desenhadas como parte da rede. O movimento de incorporação usa uma única representação temporária de H₂. Os pulsos de encaixe duram 0,35 segundo.

A composição mantém como referência as capturas oficiais de [Become Blackhole, da PandaKoala Studio](https://store.steampowered.com/app/4994890/Become_Blackhole/). A captura consultada fica em `validation/` e é excluída do pacote jogável.

## Validação sem janela

Use o caminho do executável Godot nos comandos abaixo.

```powershell
godot --headless --path . --script res://validation/universe_regression.gd
godot --headless --path . --script res://validation/headless_regression.gd
godot --headless --path . --script res://validation/crystal_routes.gd
```

A verificação `universe_regression.gd` cobre o vazio inicial, o surgimento dos elétrons e dos prótons, o controle após a abertura, as transformações normais do jogador, a formação automática de H e H₂, a movimentação do ambiente, a pausa e a retomada dos saves.

A verificação `headless_regression.gd` cobre movimento, parada, as duas primeiras transformações, o visual do próton, as órbitas, o reservatório de moléculas e a transferência para o cristal.

A verificação `crystal_routes.gd` conclui os caminhos largo e estreito em cada um dos três núcleos. Verifica a pausa durante um encaixe, o tempo de observação sem crescimento automático, a reabertura durante a nucleação e durante uma chegada, o salvamento no meio de cada percurso, as posições disponíveis ao retomar, a revelação dos outros cristais e a expansão após o marco. Também converte um save da versão anterior.

Esses testes usam saves próprios em `user://`, com nomes terminados em `_validation.json`. Os registros ficam em `validation/headless_regression.log` e `validation/crystal_routes.log`. As prévias `validation/crystal_wide.png` e `validation/crystal_narrow.png` são renderizadas em superfícies ocultas, sem movimentar o cursor.

Para gerar o pacote, use `godot --headless --path . --export-pack "Windows Portable" build/DaMateria.pck`.
