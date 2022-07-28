using System.IO;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.AspNetCore.Http;
using PgpCore;
using System.Threading.Tasks;
using System;
using Microsoft.Extensions.Logging;
using Microsoft.WindowsAzure.Storage.Blob;
using Microsoft.WindowsAzure.Storage;
using System.Collections.Concurrent;
using System.Net.Http;
using Microsoft.Azure.KeyVault.Models;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.Azure.KeyVault;
using System.Text;

namespace Neba_DecryptFile
{
    public static class DecryptFile
    {
        private static readonly HttpClient client = new HttpClient();
        private static ConcurrentDictionary<string, string> secrects = new ConcurrentDictionary<string, string>();

        private static string IsKeyVaultRefActive = Environment.GetEnvironmentVariable("KeyVaultRef_Active");
        private static string StorageAccountConnection = Environment.GetEnvironmentVariable("StorageAccountConnection");
        private static string ContainerName = Environment.GetEnvironmentVariable("ContainerName");
        private static string Directory_one = Environment.GetEnvironmentVariable("Directory_one");
        private static string Directory_two = Environment.GetEnvironmentVariable("Directory_two");
        private static string Directory_three = Environment.GetEnvironmentVariable("Directory_three");
        private static string Directory_In = Environment.GetEnvironmentVariable("InputFolder");
        private static string Directory_Out = Environment.GetEnvironmentVariable("OutputFolder");

        [FunctionName("DecryptFile")]
        public static async Task<IActionResult> Run(
            [HttpTrigger(AuthorizationLevel.Function, "get", "post", Route = null)] HttpRequest req,
            ILogger log)
        {
            log.LogInformation("C# HTTP trigger function processed a request.");
           
            string SourceFileName= Environment.GetEnvironmentVariable("SourceFileName");
            string TargetFileName = Environment.GetEnvironmentVariable("TargetFileName");
            string privateKey=null;
            string passPhrase = null;

            //Check if you want to use Keyvault code from C# or Keyvault ManagedIdentity References from Azure
            //Set 1 if you want to just use Keyvault via appsettings of Function 
            if (IsKeyVaultRefActive == "0" && IsKeyVaultRefActive != null && IsKeyVaultRefActive !=string.Empty)
            {
                log.LogInformation("Keyvault access from code started");
                //Variable Declaration

                string privateKeySecretId = Environment.GetEnvironmentVariable("SecretId"); 
                string passPhraseSecretId = Environment.GetEnvironmentVariable("Phrase"); 

                if (privateKeySecretId == null)
                {
                    return new BadRequestObjectResult("Please pass a private key secret identifier on the query string");
                }


               
                try
                {
                    privateKey = await GetFromKeyVaultAsync(privateKeySecretId);
                    log.LogInformation("Private Key Fetched");
                    if (passPhraseSecretId != null)
                    {
                        passPhrase = await GetFromKeyVaultAsync(passPhraseSecretId);
                        log.LogInformation("PassPhrase fetched");
                    }
                }
                catch (KeyVaultErrorException e) when (e.Body.Error.Code == "SecretNotFound")
                {
                    return new NotFoundResult();
                }
                catch (KeyVaultErrorException e) when (e.Body.Error.Code == "Forbidden")
                {
                    return new UnauthorizedResult();
                }
            }
            else
            {
                log.LogInformation("Keys Access started from keyvault via appsettings ");
                privateKey = Environment.GetEnvironmentVariable("SecretId");
                passPhrase= Environment.GetEnvironmentVariable("Phrase");
            }
            try
            {
                log.LogInformation("Blog container and folder processing");
                //system/import/NIMS/In/CID - Compilation Information Database_1848.zip.gpg
                CloudStorageAccount storageAccount = CloudStorageAccount.Parse(StorageAccountConnection);
                CloudBlobClient client = storageAccount.CreateCloudBlobClient();
                CloudBlobContainer container = client.GetContainerReference(ContainerName);
                CloudBlobDirectory system = container.GetDirectoryReference(Directory_one);
                CloudBlobDirectory import = system.GetDirectoryReference(Directory_two);
                CloudBlobDirectory NIMS = import.GetDirectoryReference(Directory_three);
                CloudBlobDirectory In = NIMS.GetDirectoryReference(Directory_In);

                CloudBlockBlob blockBlob = In.GetBlockBlobReference(SourceFileName);
               
                string line = "";

               
                using (var memoryStream = new MemoryStream())
                {
                    try
                    {
                        await blockBlob.DownloadToStreamAsync(memoryStream);
                        memoryStream.Position = 0;
                        // line = System.Text.Encoding.UTF8.GetString(memoryStream.ToArray());
                        log.LogInformation("Decrypt Started");
                        Stream decryptedData = await DecryptAsync(memoryStream, privateKey, passPhrase);

                        log.LogInformation("Upload to blob started");
                        uploadblob(decryptedData,TargetFileName);
                        log.LogInformation("Function Success");

                    }
                    catch (Exception ex)
                    {
                        return new BadRequestObjectResult("Error Occured while decrypting and uploading Data /n ErrorDetails: "+ex.Message +"StackTrace:"+ex.StackTrace.ToString());
                    }
                }


                return new OkObjectResult($"File Decrypted and Placed, Filename: {TargetFileName}");
                   
            }
            catch (Exception ex)
            {
                return new BadRequestObjectResult("Error :" + ex.Message);
            }
        }
        private static void uploadblob(Stream decryptedData,string targetfilename)
        {
            CloudStorageAccount storageAccount = CloudStorageAccount.Parse(StorageAccountConnection);
            CloudBlobClient client = storageAccount.CreateCloudBlobClient();
            CloudBlobContainer container = client.GetContainerReference(ContainerName);
            CloudBlobDirectory system = container.GetDirectoryReference(Directory_one);
            CloudBlobDirectory import = system.GetDirectoryReference(Directory_two);
            CloudBlobDirectory NIMS = import.GetDirectoryReference(Directory_three);
            CloudBlobDirectory In = NIMS.GetDirectoryReference(Directory_Out);
            var blockBlob = In.GetBlockBlobReference(targetfilename);
            try {

                blockBlob.UploadFromStreamAsync(decryptedData);
                System.Threading.Thread.Sleep(5000);
            }
            catch(Exception ex) { throw ex; }
            

        }

        private static async Task<Stream> DecryptAsync(Stream inputStream, string privateKey, string passPhrase)
        {
            using (PGP pgp = new PGP())
            {
                Stream outputStream = new MemoryStream();

                using (inputStream)
                    try
                    {
                        using (Stream privateKeyStream = GenerateStreamFromString(privateKey))
                        {

                            await pgp.DecryptStreamAsync(inputStream, outputStream, privateKeyStream, passPhrase);
                            outputStream.Position = 0;

                            return outputStream;
                        }
                    }
                    catch(Exception ex)
                    {
                        throw ex;
                    }
            }
        }
        private static async Task<string> GetFromKeyVaultAsync(string secretIdentifier)
        {
            if (!secrects.ContainsKey(secretIdentifier))
            {
                var azureServiceTokenProvider = new AzureServiceTokenProvider();
                var authenticationCallback = new KeyVaultClient.AuthenticationCallback(azureServiceTokenProvider.KeyVaultTokenCallback);
                var kvClient = new KeyVaultClient(authenticationCallback, client);

                SecretBundle secretBundle = await kvClient.GetSecretAsync(secretIdentifier);
                //byte[] data = Convert.FromBase64String(secretBundle.Value);
                //secrects[secretIdentifier] = Encoding.UTF8.GetString(data);

                //// //byte[] data = Encoding.ASCII.GetBytes(secretBundle.Value);
                //// //secrects[secretIdentifier] = Encoding.ASCII.GetString(data);
                secrects[secretIdentifier] = secretBundle.Value;

            }
            return secrects[secretIdentifier];
        }

        

        private static Stream GenerateStreamFromString(string s)
        {
            MemoryStream stream = new MemoryStream();
            StreamWriter writer = new StreamWriter(stream);
            writer.Write(s);
            writer.Flush();
            stream.Position = 0;
            return stream;
        }

        #region Local.json setting to be added
        //        {
        //    "IsEncrypted": false,
        //  "Values": {
        //    "AzureWebJobsStorage": "UseDevelopmentStorage=false",
        //    "FUNCTIONS_WORKER_RUNTIME": "dotnet",
        //    "SecretId": "Secret key from keyuvault with version",
        //    "Phrase": "Secret phrase from keyuvault with version",
        //    "KeyVaultRef_Active": "0",
        //    "StorageAccountConnection": "Storage account Connection string",
        //    "ContainerName": "gdrive",
        //    "Directory_one": "system",
        //    "Directory_two": "import",
        //    "Directory_three": "NIMS",

        //    "InputFolder": "In",
        //    "OutputFolder": "processed",
        //    "SourceFileName": "CID - Compilation Information Database_1848.zip.gpg",
        //    "TargetFileName": "CID - Compilation Information Database_1848.zip"

        //  }
        //}
        #endregion


    }
}
