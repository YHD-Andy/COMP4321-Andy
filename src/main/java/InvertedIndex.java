import jdbm.RecordManager;
import jdbm.RecordManagerFactory;
import jdbm.htree.HTree;
import jdbm.helper.FastIterator;
import java.util.Vector;
import java.io.IOException;
import java.io.Serializable;

class Posting implements Serializable
{
	public String doc;
	public int freq;
	Posting(String doc, int freq)
	{
		this.doc = doc;
		this.freq = freq;
	}
}

public class InvertedIndex
{
	private RecordManager recman;
	private HTree hashtable;

	InvertedIndex(String recordmanager, String objectname) throws IOException
	{
		recman = RecordManagerFactory.createRecordManager(recordmanager);
		long recid = recman.getNamedObject(objectname);
			
		if (recid != 0)
			hashtable = HTree.load(recman, recid);
		else
		{
			hashtable = HTree.createInstance(recman);
			recman.setNamedObject(objectname, hashtable.getRecid());
		}
	}


	public void finalize() throws IOException
	{
		recman.commit();
		recman.close();				
	} 

	public void addEntry(String word, int x, int y) throws IOException
	{
		// Add a "docX Y" entry for the key "word" into hashtable
		String newEntry = "doc" + x + " " + y;
		String oldContent = (String) hashtable.get(word);

		if (oldContent == null || oldContent.length() == 0)
		{
			hashtable.put(word, newEntry);
		}
		else
		{
			hashtable.put(word, oldContent + " " + newEntry);
		}

	}
	public void delEntry(String word) throws IOException
	{
		// Delete the word and its list from the hashtable
		hashtable.remove(word);

	} 
	public void printAll() throws IOException
	{
		// Print all the data in the hashtable
		FastIterator iter = hashtable.keys();
		String key;
		Vector<String> keys = new Vector<String>();

		while ((key = (String) iter.next()) != null)
		{
			keys.add(key);
		}

		java.util.Collections.sort(keys);
		for (String k : keys)
		{
			System.out.println(k + " = " + hashtable.get(k));
		}

	}	
	
	public static void main(String[] args)
	{
		try
		{
			InvertedIndex index = new InvertedIndex("lab1.db", "ht1");

			// Ensure deterministic sample output when rerunning the program.
			index.delEntry("cat");
			index.delEntry("dog");
	
			index.addEntry("cat", 2, 6);
			index.addEntry("dog", 1, 33);
			System.out.println("First print");
			index.printAll();
			
			index.addEntry("cat", 8, 3);
			index.addEntry("dog", 6, 73);
			index.addEntry("dog", 8, 83);
			index.addEntry("dog", 10, 5);
			index.addEntry("cat", 11, 106);
			System.out.println("Second print");
			index.printAll();
			
			index.delEntry("dog");
			System.out.println("Third print");
			index.printAll();
			index.finalize();
		}
		catch(IOException ex)
		{
			System.err.println(ex.toString());
		}
	}
}
