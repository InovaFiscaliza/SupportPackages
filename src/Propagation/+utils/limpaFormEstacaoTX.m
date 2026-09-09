function limpaFormEstacaoTX(app)
% remove os dados de input do agrupamento estação transmissora

app.IdentificaoEditField.Value = '';
app.FrequnciaMHzEditField.Value = 0;
app.PotnciaWattsEditField.Value = 0;
app.LatitudeEditField.Value = 0;
app.LongitudeEditField.Value = 0;
app.AlturaEditField_2.Value = 0;
app.TiltEditField.Value = 0;
app.AzimuteEditField.Value = 0;
app.txAntenna.Value = '';
app.txAntenna.UserData = [];
app.txAntenna.HorizontalAlignment = 'left';

end

